import SwiftUI

struct EditorRoute: Identifiable {
    let id = UUID()
    let event: Event?
}

@MainActor
struct EventEditor: View {
    @ObservedObject var model: DayModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFocused: Bool
    @State private var title: String
    @State private var kind: EventKind
    @State private var day: CivilDay?
    @State private var month: CivilDay
    @State private var jumping = false
    @State private var jumpDate: Date
    let event: Event?

    init(model: DayModel, event: Event?) {
        self.model = model
        self.event = event
        let initial = event?.day ?? model.today
        _title = State(initialValue: event?.title ?? "")
        _kind = State(initialValue: event?.kind ?? .countdown)
        _day = State(initialValue: event?.day)
        _month = State(initialValue: CivilDay(initial.year, initial.month, 1))
        _jumpDate = State(initialValue: initial.date(in: model.calendar, hour: 12) ?? model.now)
    }

    private var canSave: Bool {
        guard let day else { return false }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return DateCard(title: trimmed, kind: kind, day: day).isValid && !model.saving
            && (kind == .countdown || day <= model.today || (event?.kind == .elapsed && event?.day == day))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField(L.t("editor.name"), text: $title)
                        .font(.title3.weight(.semibold)).textFieldStyle(.roundedBorder)
                        .focused($nameFocused).submitLabel(.done)
                        .onSubmit { nameFocused = false }
                        .accessibilityIdentifier("editor.name")
                    HStack(spacing: 5) {
                        ForEach(EventKind.allCases) { option in
                            Button {
                                kind = option
                                if option == .elapsed, let day, day > model.today, event?.kind != .elapsed {
                                    self.day = nil
                                }
                            } label: {
                                Text(option.label)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 14).frame(minHeight: 44)
                                    .foregroundStyle(kind == option ? Color.white : Palette.muted)
                                    .background(kind == option ? Palette.blue : Palette.pale, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(kind == option ? .isSelected : [])
                            .accessibilityIdentifier("editor.kind." + option.rawValue)
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L.t(kind == .elapsed ? "editor.start" : "editor.date")).font(.headline)
                        Text(day?.formatted(.plain) ?? L.t("editor.choose")).font(.subheadline)
                            .foregroundStyle(Palette.muted).accessibilityIdentifier("editor.selected")
                    }
                    calendarGrid
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.paper)
            .navigationTitle(L.t(event == nil ? "home.create" : "event.edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("common.cancel")) { dismiss() }.accessibilityIdentifier("editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("common.save")) {
                        guard let day else { return }
                        Task {
                            if await model.save(title: title, kind: kind, day: day, replacing: event?.id) { dismiss() }
                        }
                    }
                    .disabled(!canSave).accessibilityIdentifier("editor.save")
                }
            }
            .task {
                guard event == nil else { return }
                try? await Task.sleep(for: .milliseconds(250))
                if !Task.isCancelled { nameFocused = true }
            }
            .sheet(isPresented: $jumping) {
                NavigationStack {
                    DatePicker(L.t("editor.jump"), selection: $jumpDate, displayedComponents: .date)
                        .datePickerStyle(.wheel).labelsHidden().padding()
                        .navigationTitle(L.t("editor.jump")).navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(L.t("common.cancel")) { jumping = false }.accessibilityIdentifier("editor.jump-cancel")
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button(L.t("common.done")) {
                                    let day = CivilDay(jumpDate, in: model.calendar)
                                    month = CivilDay(day.year, day.month, 1)
                                    jumping = false
                                }.accessibilityIdentifier("editor.jump-done")
                            }
                        }
                }
                .presentationDetents([.medium])
            }
        }
    }

    private var calendarGrid: some View {
        let calendar = model.calendar
        let first = month.date(in: calendar, hour: 12) ?? model.now
        let weekdays = calendar.veryShortStandaloneWeekdaySymbols
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let count = month.daysInMonth
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        return VStack(spacing: 7) {
            HStack {
                monthArrow(-1)
                Spacer()
                Button(month.formatted(.month)) {
                    nameFocused = false
                    jumpDate = first
                    jumping = true
                }
                .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                .accessibilityIdentifier("editor.jump")
                Spacer()
                monthArrow(1)
            }
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(0..<7) { index in
                    Text(weekdays[(calendar.firstWeekday - 1 + index) % 7])
                        .font(.caption).foregroundStyle(Palette.muted).accessibilityHidden(true)
                }
                ForEach(0..<offset, id: \.self) { _ in Color.clear.frame(height: 44).accessibilityHidden(true) }
                ForEach(1...count, id: \.self) { number in
                    let candidate = CivilDay(month.year, month.month, number)
                    Button {
                        day = candidate
                        nameFocused = false
                    } label: {
                        Text(number.formatted()).font(.subheadline.weight(day == candidate ? .bold : .regular))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(day == candidate ? Palette.blue : .clear, in: Circle())
                            .foregroundStyle(day == candidate ? Color.white : Palette.ink)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(kind == .elapsed && candidate > model.today && candidate != day)
                    .opacity(kind == .elapsed && candidate > model.today && candidate != day ? 0.35 : 1)
                    .accessibilityLabel(candidate.formatted(.full))
                    .accessibilityAddTraits(day == candidate ? .isSelected : [])
                    .accessibilityIdentifier("day." + String(candidate.ordinal))
                }
            }
        }
    }

    private func monthArrow(_ amount: Int) -> some View {
        Button {
            nameFocused = false
            let index = (month.year - 1) * 12 + month.month - 1 + amount
            guard (0..<(9999 * 12)).contains(index) else { return }
            month = CivilDay(index / 12 + 1, index % 12 + 1, 1)
        } label: {
            Image(systemName: amount < 0 ? "chevron.left" : "chevron.right")
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(L.t(amount < 0 ? "editor.previous" : "editor.next"))
        .accessibilityIdentifier(amount < 0 ? "editor.previous" : "editor.next")
    }
}
