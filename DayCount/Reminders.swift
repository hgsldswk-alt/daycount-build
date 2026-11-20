import Foundation
import UserNotifications

struct ReminderPlan: Equatable {
    static let namespace = "daycount."
    static let offsets = [1, 3, 7]
    let id: String
    let title: String
    let fireDate: Date
    let components: DateComponents
    let offset: Int

    static func id(for event: Event, offset: Int) -> String { namespace + event.id.uuidString + "." + String(offset) }

    static func plans(events: [Event], now: Date, calendar: Calendar) -> [Self] {
        events.flatMap { event -> [Self] in
            guard event.kind == .countdown else { return [] }
            var values = event.sameDay ? [0] : []
            if let advance = event.advance, offsets.contains(advance) { values.append(advance) }
            return values.compactMap { offset in
                guard let day = event.day.adding(days: -offset),
                      let fire = day.date(in: calendar, hour: 9), fire > now else { return nil }
                var components = day.components
                components.calendar = Calendar(identifier: .gregorian)
                components.hour = 9
                components.minute = 0
                components.second = 0
                return Self(id: id(for: event, offset: offset), title: event.title, fireDate: fire,
                            components: components, offset: offset)
            }
        }.sorted { $0.fireDate == $1.fireDate ? $0.id < $1.id : $0.fireDate < $1.fireDate }
    }
}

enum ReminderStatus: Equatable {
    case off, checking, denied, past, scheduled, capacity, failed

    var label: String {
        switch self {
        case .off: return L.t("reminder.off")
        case .checking: return L.t("reminder.checking")
        case .denied: return L.t("reminder.denied")
        case .past: return L.t("reminder.past")
        case .scheduled: return L.t("reminder.scheduled")
        case .capacity: return L.t("reminder.capacity")
        case .failed: return L.t("reminder.failed")
        }
    }
}

actor ReminderService {
    private let center = UNUserNotificationCenter.current()

    func requestIfNeeded() async {
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }
    }

    func reconcile(events: [Event], now: Date, calendar: Calendar, fixture: String?) async -> [String: ReminderStatus] {
        let plans = ReminderPlan.plans(events: events, now: now, calendar: calendar)
        var status: [String: ReminderStatus] = [:]
        let upcoming = Set(plans.map(\.id))
        for event in events where event.kind == .countdown {
            let offsets = (event.sameDay ? [0] : []) + (event.advance.map { [$0] } ?? [])
            for offset in offsets {
                let id = ReminderPlan.id(for: event, offset: offset)
                status[id] = upcoming.contains(id) ? .checking : .past
            }
        }

        if let fixture {
            for (index, plan) in plans.enumerated() {
                status[plan.id] = fixture == "denied" ? .denied : (index < 64 ? .scheduled : .capacity)
            }
            return status
        }

        let settings = await center.notificationSettings()
        let allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        let pending = await center.pendingNotificationRequests()
        let ours = pending.filter { $0.identifier.hasPrefix(ReminderPlan.namespace) }
        let available = max(0, 64 - (pending.count - ours.count))
        let retained = allowed ? Set(plans.prefix(available).map(\.id)) : []
        center.removePendingNotificationRequests(withIdentifiers: ours.map(\.identifier).filter { !retained.contains($0) })

        for plan in plans {
            guard allowed else { status[plan.id] = .denied; continue }
            guard retained.contains(plan.id) else { status[plan.id] = .capacity; continue }

            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.offset == 0 ? L.t("notification.today")
                : L.f(plan.offset == 1 ? "notification.advance.one" : "notification.advance", plan.offset)
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: plan.components, repeats: false)
            if let existing = ours.first(where: { $0.identifier == plan.id }),
               let existingTrigger = existing.trigger as? UNCalendarNotificationTrigger,
               existingTrigger.dateComponents == plan.components,
               existing.content.title == content.title, existing.content.body == content.body {
                status[plan.id] = .scheduled
                continue
            }
            do {
                try await center.add(UNNotificationRequest(identifier: plan.id, content: content, trigger: trigger))
                status[plan.id] = .scheduled
            } catch {
                center.removePendingNotificationRequests(withIdentifiers: [plan.id])
                status[plan.id] = .failed
            }
        }
        return status
    }
}
