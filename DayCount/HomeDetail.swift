import SwiftUI
import UIKit

@MainActor
struct HomeView: View {
    @ObservedObject var model: DayModel
    @ObservedObject var purchases: Purchases
    let open: (UUID) -> Void
    let create: () -> Void
    let importCode: () -> Void
    let importFile: () -> Void
    let help: () -> Void
    let unlock: () -> Void
    let export: () -> Void
    let review: () -> Void
    let shareRequested: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack {
                    Text(model.today.formatted(.shortWeekday)).font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.muted).accessibilityIdentifier("home.date")
                    Spacer(minLength: 6)
                    more
                    if model.featured != nil {
                        Button(action: create) { Label(L.t("home.new"), systemImage: "plus") }
                            .buttonStyle(PrimaryButtonStyle(compact: true)).accessibilityIdentifier("home.new")
                    }
                }
                Text(L.t("home.title")).font(.largeTitle.weight(.bold))
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("home.title")
                if let featured = model.featured {
                    hero(featured)
                    let other = model.ordered.filter { $0.id != featured.id }
                    if !other.isEmpty {
                        Text(L.t("home.others")).font(.subheadline.weight(.bold))
                            .accessibilityAddTraits(.isHeader).padding(.top, 5)
                        VStack(spacing: 0) {
                            ForEach(other) { event in
                                if event.id != other.first?.id { Divider() }
                                row(event)
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(L.t("home.empty")).foregroundStyle(Palette.muted)
                        Button(action: create) { Label(L.t("home.create"), systemImage: "plus") }
                            .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("home.new")
                    }
                    .padding(.top, 16)
                }
                if shareRequested { ShareConfirmation() }
            }
            .padding(.horizontal, 23)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    private var more: some View {
        Menu {
            Button(L.t("import.code"), systemImage: "text.document", action: importCode)
                .accessibilityIdentifier("home.import-code")
            Button(L.t("import.file"), systemImage: "folder", action: importFile)
                .accessibilityIdentifier("home.import-file")
            if !model.data.events.isEmpty {
                Button(L.t("home.export"), systemImage: "square.and.arrow.up.on.square") {
                    if Launch.isFree || purchases.entitlement?.hasPro(at: model.currentTime) == true { export() }
                    else { unlock() }
                }.accessibilityIdentifier("home.export")
            }
            if !Launch.isFree {
                Button(L.t("purchase.title"), systemImage: "sparkles", action: unlock)
                    .accessibilityIdentifier("home.paywall")
            }
            Button(L.t("home.help"), systemImage: "questionmark.circle", action: help)
                .accessibilityIdentifier("home.help")
            Button(L.t("home.review"), systemImage: "star", action: review)
                .accessibilityIdentifier("home.review")
        } label: {
            RoundIcon(systemName: "ellipsis")
        }
        .accessibilityLabel(L.t("home.more"))
        .accessibilityIdentifier("home.more")
    }

    private func hero(_ event: Event) -> some View {
        let read = model.dayReading(event)
        return Button { open(event.id) } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    if event.pin != nil { Text(L.t("event.pinned")) }
                    Spacer()
                    if read.state != .today { Text(read.prefix) }
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                Text(event.title).font(.title2.weight(.bold)).lineLimit(3)
                    .padding(.top, 6)
                LargeReading(reading: read)
                Spacer(minLength: 0)
                Rectangle().fill(.white.opacity(0.35)).frame(height: 1)
                HStack {
                    Text(event.day.formatted(.shortWeekday)).font(.footnote)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                }
                .padding(.vertical, 7)
            }
            .padding(19)
            .frame(minHeight: 284, alignment: .topLeading)
            .foregroundStyle(.white)
            .background(Palette.blue, in: RoundedRectangle(cornerRadius: 25))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.f("widget.accessibility", event.title, read.text, event.day.formatted(.shortWeekday)))
        .accessibilityIdentifier("home.featured")
    }

    private func row(_ event: Event) -> some View {
        let read = model.dayReading(event)
        return Button { open(event.id) } label: {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                    Text(event.day.formatted(.short)).font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 2)
                compactReading(read)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Palette.muted)
            }
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L.f("widget.accessibility", event.title, read.text, event.day.formatted(.short)))
        .accessibilityIdentifier("home.event")
    }

    @ViewBuilder
    private func compactReading(_ read: DayReading) -> some View {
        if read.state == .today {
            Text(read.text).font(.caption.weight(.semibold)).foregroundStyle(Palette.accent)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if read.state != .starts { Text(read.prefix).font(.caption) }
                Text(read.days.formatted()).font(.title3.weight(.bold)).monospacedDigit()
                Text(read.unit).font(.caption)
            }
            .foregroundStyle(Palette.accent)
            .lineLimit(1).minimumScaleFactor(0.6)
        }
    }
}

@MainActor
struct EventDetail: View {
    @ObservedObject var model: DayModel
    @ObservedObject var purchases: Purchases
    @Environment(\.openURL) private var openURL
    let event: Event
    let shareRequested: Bool
    let back: () -> Void
    let edit: () -> Void
    let unlock: () -> Void
    let shareImage: () -> Void
    let shareFile: () -> Void
    let copy: () -> Void
    let copyTopic: () -> Void
    let deleted: () -> Void
    @State private var advance = false
    @State private var confirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar.padding(.horizontal, 23).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text(event.title).font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("event.title")
                        Text(event.day.formatted()).font(.subheadline).foregroundStyle(Palette.muted)
                    }
                    .padding(.top, 15)
                    reading
                    controls
                    if shareRequested { ShareConfirmation() }
                }
                .padding(.horizontal, 23)
                .padding(.vertical, 14)
            }
            Button(L.t("event.share"), action: shareImage)
                .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("event.share")
                .padding(.horizontal, 23).padding(.vertical, 8)
        }
        .frame(maxWidth: 620).frame(maxWidth: .infinity)
        .alert(L.t("event.delete-confirm"), isPresented: $confirmingDelete) {
            Button(L.t("common.cancel"), role: .cancel) { }
            Button(L.t("event.delete"), role: .destructive) {
                Task { if await model.delete(event.id) { deleted() } }
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Button(action: back) { Label(L.t("event.back"), systemImage: "chevron.left").font(.subheadline.weight(.semibold)) }
                .frame(minHeight: 44).accessibilityIdentifier("event.back")
            Spacer()
            Text(L.t("event.detail")).font(.subheadline.weight(.semibold))
            Spacer()
            Menu {
                Button(L.t("event.edit"), systemImage: "pencil", action: edit).accessibilityIdentifier("event.edit")
                Button(L.t(event.pin == nil ? "event.pin" : "event.unpin"), systemImage: "pin") {
                    let limit = purchases.entitlement?.pinLimit(at: model.currentTime) ?? (Launch.isFree ? 3 : 1)
                    if event.pin == nil && model.data.events.filter({ $0.pin != nil }).count >= limit {
                        if limit == 1 { unlock() }
                        else { model.message = L.t("event.pin-limit") }
                    } else { Task { await model.togglePin(event, entitlement: purchases.entitlement) } }
                }.accessibilityIdentifier("event.pin")
                Button(L.t("event.share-file"), systemImage: "doc", action: shareFile).accessibilityIdentifier("event.share-file")
                Button(L.t("event.copy-code"), systemImage: "doc.on.doc", action: copy).accessibilityIdentifier("event.copy-code")
                Button(L.t("share.copy-topic"), systemImage: "number", action: copyTopic).accessibilityIdentifier("event.copy-topic")
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label(L.t("event.delete"), systemImage: "trash")
                }.accessibilityIdentifier("event.delete")
            } label: { RoundIcon(systemName: "ellipsis") }
            .accessibilityLabel(L.t("event.more")).accessibilityIdentifier("event.more")
        }
    }

    private var reading: some View {
        let read = model.dayReading(event)
        return VStack(alignment: .leading, spacing: 0) {
            if read.state != .today { Text(read.prefix).font(.subheadline.weight(.semibold)).accessibilityHidden(true) }
            LargeReading(reading: read).accessibilityIdentifier("event.reading")
        }
        .frame(maxWidth: .infinity, minHeight: 155, alignment: .leading)
        .foregroundStyle(Palette.accent)
        .padding(19)
        .background(Palette.pale, in: RoundedRectangle(cornerRadius: 25))
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            if event.kind == .countdown {
                let status = model.reminderStatus(event, offset: 0)
                Toggle(isOn: Binding(get: { event.sameDay }, set: { enabled in
                    Task { await model.setReminder(event.id, enabled: enabled) }
                })) {
                    Text(L.t("reminder.same-day")).font(.subheadline.weight(.semibold))
                }
                .tint(Palette.blue).padding(.vertical, 8).frame(minHeight: 52)
                .disabled(model.saving).accessibilityIdentifier("reminder.toggle")
                if event.sameDay {
                    Text(status.label).font(.caption).foregroundStyle(Palette.muted)
                        .padding(.bottom, 8).accessibilityIdentifier("reminder.status")
                }
                Divider()
                Button {
                    if event.advance == nil && !canAddAdvance { unlock() }
                    else { advance = true }
                } label: {
                    let value = event.advance.map { offset in
                        L.f("reminder.value", offsetLabel(offset), model.reminderStatus(event, offset: offset).label)
                    }
                    ControlLabel(title: L.t("reminder.advance"), value: value ?? L.t("reminder.unset"))
                }
                .buttonStyle(.plain).disabled(model.saving).accessibilityIdentifier("reminder.advance")
                .confirmationDialog(L.t("reminder.advance"), isPresented: $advance, titleVisibility: .visible) {
                    if canAddAdvance {
                        ForEach(ReminderPlan.offsets, id: \.self) { offset in
                            Button(offsetLabel(offset)) {
                                if canAddAdvance {
                                    Task { await model.setReminder(event.id, advance: offset, editingAdvance: true) }
                                } else { unlock() }
                            }
                        }
                    } else {
                        Button(L.t("purchase.title"), action: unlock)
                    }
                    if event.advance != nil {
                        Button(L.t("reminder.remove"), role: .destructive) {
                            Task { await model.setReminder(event.id, editingAdvance: true) }
                        }
                    }
                    Button(L.t("common.cancel"), role: .cancel) {}
                }
                Divider()
                if status == .denied || event.advance.map({ model.reminderStatus(event, offset: $0) == .denied }) == true {
                    Button(L.t("reminder.settings")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }.frame(minHeight: 44).accessibilityIdentifier("reminder.settings")
                    Divider()
                }
            }
            Button {
                Task { await model.setWidget(model.data.widgetID == event.id ? nil : event.id) }
            } label: {
                ControlLabel(title: L.t("widget.select"), value: widgetState)
            }
            .buttonStyle(.plain)
            .disabled(model.saving)
            .accessibilityIdentifier("widget.select")
            .accessibilityValue(widgetState)
            Divider()
        }
    }

    private var canAddAdvance: Bool { Launch.isFree || purchases.entitlement?.hasPro(at: model.currentTime) == true }
    private var widgetState: String {
        if model.data.widgetID == event.id { return L.t("widget.selected") }
        if model.data.widgetID == nil { return L.t("widget.auto") }
        return L.t("widget.other")
    }

    private func offsetLabel(_ offset: Int) -> String {
        L.f(offset == 1 ? "reminder.offset.one" : "reminder.offset", offset)
    }
}

struct ShareConfirmation: View {
    var body: some View {
        Text(L.t("share.requested")).font(.caption).foregroundStyle(Palette.muted)
            .accessibilityIdentifier("share.requested")
    }
}
