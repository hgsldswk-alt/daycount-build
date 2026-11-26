import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class DayModel: ObservableObject {
    @Published private(set) var data = AppData()
    @Published private(set) var now: Date
    @Published private(set) var zone: TimeZone = .current
    @Published private(set) var ready = false
    @Published private(set) var loadFailed = false
    @Published private(set) var saving = false
    @Published private(set) var reminders: [String: ReminderStatus] = [:]
    @Published var message: String?

    let testing: Bool
    let storeDemo: Bool
    let widgetCapture: Bool
    let expired: Bool
    let startPaywall: Bool
    private let reset: Bool
    private let reminderFixture: String?
    private let fixedNow: Date?
    private let store: LocalStore
    private let reminderService = ReminderService()
    private var started = false
    private var reminderTask: Task<Void, Never>?
    private var reminderRevision = 0
    private var widgetDirty = true
    private var mayReview = false

    var calendar: Calendar { CivilDay.localCalendar(zone) }
    var today: CivilDay { CivilDay(now, in: calendar) }
    var currentTime: Date { fixedNow ?? Date() }
    var ordered: [Event] { Event.ordered(data.events, today: today) }
    var featured: Event? { Event.featured(data.events, today: today) }
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1" }

    init(arguments: [String] = ProcessInfo.processInfo.arguments,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        testing = arguments.contains("-ui-testing")
        storeDemo = testing && arguments.contains("-store-demo")
        widgetCapture = storeDemo && arguments.contains("-widget-capture")
        expired = testing && (arguments.contains("-expired") || arguments.contains("-paywall"))
        startPaywall = testing && arguments.contains("-paywall")
        reset = testing && arguments.contains("-reset")
        reminderFixture = testing ? (environment["DAYCOUNT_NOTIFICATIONS"] ?? "authorized") : nil
        let base = CivilDay(2026, 11, 19).date(in: CivilDay.localCalendar(), hour: 12)
        fixedNow = testing ? base : nil
        now = fixedNow ?? Date()
        let runtime = environment["DAYCOUNT_TEST_RUN"].flatMap(UUID.init(uuidString:)) ?? UUID()
        let location = testing
            ? FileManager.default.temporaryDirectory.appendingPathComponent("DayCountUITests-" + runtime.uuidString, isDirectory: true)
            : URL.applicationSupportDirectory.appendingPathComponent("DayCount", isDirectory: true)
        store = LocalStore(directory: location)
    }

    deinit { reminderTask?.cancel() }

    func start() async {
        guard !started else { return }
        started = true
        loadFailed = false
        do {
            var initial = try await store.load(reset: reset)
            if storeDemo && initial.events.isEmpty { initial.events = demoEvents() }
            mayReview = !initial.review.dates.isEmpty
            let recordedDates = initial.review.dates
            if !testing { initial.review.record(today) }
            data = initial
            if storeDemo || initial.review.dates != recordedDates {
                do { try await store.save(initial) }
                catch { initial.review.dates = recordedDates; data = initial }
            }
            ready = true
            await updateWidget()
            reconcile()
        } catch {
            loadFailed = true
            started = false
        }
    }

    func activate() async {
        guard ready else { return }
        let previousDay = today
        let previousZone = zone
        zone = .current
        now = fixedNow ?? Date()
        let changed = previousDay != today || previousZone != zone
        if !testing && !data.review.dates.contains(today) && data.review.dates.count < 3 {
            _ = await change { $0.review.record(self.today) }
        }
        if changed || widgetDirty { await updateWidget() }
        reconcile()
    }

    func dayReading(_ event: Event) -> DayReading { DayReading(kind: event.kind, target: event.day, today: today) }
    func event(_ id: UUID) -> Event? { data.events.first { $0.id == id } }

    func save(title: String, kind: EventKind, day: CivilDay, replacing originalID: UUID?) async -> Bool {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let card = DateCard(title: title, kind: kind, day: day)
        guard card.isValid else { return false }
        let original = originalID.flatMap(event)
        if originalID != nil && original == nil { return false }
        if kind == .elapsed && day > today && !(original?.kind == .elapsed && original?.day == day) { return false }
        var next = original ?? Event(title: title, kind: kind, day: day, createdAt: now, modifiedAt: now)
        next.title = title
        next.kind = kind
        next.day = day
        next.modifiedAt = now
        if kind == .elapsed { next.sameDay = false; next.advance = nil }
        let saved = await change {
            if let index = $0.events.firstIndex(where: { $0.id == next.id }) { $0.events[index] = next }
            else { $0.events.append(next) }
            $0.review.saved = true
            if original == nil { $0.coreReviewProgress = .recording($0.coreReviewProgress) }
        }
        if saved && original == nil && !testing { CoreReview.shared.record(data.coreReviewProgress) }
        return saved
    }

    func delete(_ id: UUID) async -> Bool {
        await change {
            $0.events.removeAll { $0.id == id }
            if $0.widgetID == id { $0.widgetID = nil }
        }
    }

    func setWidget(_ id: UUID?) async {
        guard await change({ $0.widgetID = id }) else { return }
        if widgetDirty && (!testing || widgetCapture) { self.message = L.t("error.widget") }
    }

    func togglePin(_ event: Event, entitlement: Entitlement?) async {
        let limit = entitlement?.pinLimit(at: currentTime) ?? (Launch.isFree ? 3 : 1)
        await update(event.id) { value in
            if value.pin != nil { value.pin = nil }
            else if self.data.events.filter({ $0.pin != nil }).count < limit {
                value.pin = (self.data.events.compactMap(\.pin).max() ?? 0) + 1
            }
        }
    }

    func setReminder(_ id: UUID, enabled: Bool? = nil, advance: Int? = nil, editingAdvance: Bool = false) async {
        guard event(id)?.kind == .countdown else { return }
        let enabledRule = enabled == true || advance != nil
        guard await update(id, requestPermission: enabledRule, transform: { event in
            if let enabled { event.sameDay = enabled }
            if editingAdvance { event.advance = advance }
        }) else { return }
    }

    func reminderStatus(_ event: Event, offset: Int) -> ReminderStatus {
        guard offset == 0 ? event.sameDay : event.advance == offset else { return .off }
        return reminders[ReminderPlan.id(for: event, offset: offset)] ?? .checking
    }

    func importCards(_ cards: [DateCard]) async -> Bool {
        let additions = DateCardCodec.additions(cards, to: data.events, at: now)
        guard !additions.isEmpty else {
            self.message = L.t("import.all-duplicates")
            return true
        }
        let success = await change {
            $0.events.append(contentsOf: additions)
            $0.review.saved = true
        }
        if success && additions.count < cards.count { self.message = L.f("import.added", additions.count, cards.count - additions.count) }
        return success
    }

    func completedShare() async {
        guard !testing, !data.review.shared else { return }
        for _ in 0..<20 {
            if !saving { _ = await change { $0.review.shared = true }; return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    var reviewedThisVersion: Bool { data.review.requestedVersion == version }

    func markReviewRequested() async {
        await change { $0.review.requestedVersion = self.version }
    }

    func requestSharedReview(_ request: () -> Void) {
        guard ready, !testing, !saving, mayReview, data.review.isReady(version: version),
              CoreReview.shared.attempt(request) else { return }
        Task { await markReviewRequested() }
    }

    private func update(_ id: UUID, requestPermission: Bool = false, transform: (inout Event) -> Void) async -> Bool {
        guard let index = data.events.firstIndex(where: { $0.id == id }) else { return false }
        return await change(requestPermission: requestPermission) { next in
            transform(&next.events[index])
            next.events[index].modifiedAt = self.now
        }
    }

    @discardableResult
    private func change(requestPermission: Bool = false, _ transform: (inout AppData) -> Void) async -> Bool {
        guard ready, !saving else { return false }
        saving = true
        defer { saving = false }
        var next = data
        transform(&next)
        do {
            try await store.save(next)
            let datesChanged = data.events != next.events || data.widgetID != next.widgetID
            data = next
            if datesChanged {
                await updateWidget()
                reconcile(askingPermission: requestPermission)
            }
            return true
        } catch {
            self.message = L.t("error.write")
            return false
        }
    }

    private func updateWidget() async {
        guard !testing || widgetCapture else { widgetDirty = false; return }
        do {
            try await store.syncWidget(data, previewDay: widgetCapture ? today : nil)
            widgetDirty = false
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
        } catch { widgetDirty = true }
    }

    private func reconcile(askingPermission: Bool = false) {
        let oldTask = reminderTask
        reminderRevision += 1
        let stamp = reminderRevision
        let events = data.events, now = now, calendar = calendar
        reminderTask = Task { [weak self, reminderService, reminderFixture] in
            await oldTask?.value
            guard !Task.isCancelled else { return }
            if askingPermission && reminderFixture == nil &&
                !ReminderPlan.plans(events: events, now: now, calendar: calendar).isEmpty {
                await reminderService.requestIfNeeded()
            }
            let status = await reminderService.reconcile(events: events, now: now, calendar: calendar, fixture: reminderFixture)
            if self?.reminderRevision == stamp { self?.reminders = status }
        }
    }

    private func demoEvents() -> [Event] {
        [
            Event(title: L.t("demo.exam"), kind: .countdown, day: CivilDay(2026, 12, 7), pin: 1, sameDay: true),
            Event(title: L.t("demo.deadline"), kind: .countdown, day: CivilDay(2026, 12, 2)),
            Event(title: L.t("demo.trip"), kind: .countdown, day: CivilDay(2026, 12, 24)),
            Event(title: L.t("demo.home"), kind: .elapsed, day: CivilDay(2026, 10, 1))
        ]
    }
}
