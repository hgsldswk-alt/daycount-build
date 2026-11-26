import Foundation

struct WidgetSnapshot: Codable {
    static let group = "group.com.hgsldswk.daycount"
    static let kind = "DayCountWidget"
    private static let filename = "daycount-widget-v1.json"

    struct Card: Codable, Identifiable {
        let id: UUID
        let title: String
        let kind: EventKind
        let day: CivilDay
        let pin: Int?

        init(_ event: Event) {
            id = event.id
            title = event.title
            kind = event.kind
            day = event.day
            pin = event.pin
        }

        func reading(today: CivilDay) -> DayReading { DayReading(kind: kind, target: day, today: today) }
    }

    let selected: UUID?
    let cards: [Card]
    let previewDay: CivilDay?

    init(events: [Event], selected: UUID?, previewDay: CivilDay? = nil) {
        self.selected = selected
        self.previewDay = previewDay
        cards = events.sorted {
            if $0.createdAt == $1.createdAt { return $0.id.uuidString < $1.id.uuidString }
            return $0.createdAt < $1.createdAt
        }.map(Card.init)
    }

    func card(today: CivilDay) -> Card? {
        if let selected, let card = cards.first(where: { $0.id == selected }) { return card }
        if let pinned = cards.filter({ $0.pin != nil }).min(by: { ($0.pin ?? 0) < ($1.pin ?? 0) }) { return pinned }
        if let upcoming = cards.filter({ $0.kind == .countdown && $0.day >= today }).min(by: { $0.day < $1.day }) { return upcoming }
        return cards.filter { $0.day <= today }.max(by: { $0.day < $1.day }) ?? cards.max(by: { $0.day < $1.day })
    }

    static func read() -> Self? {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let data = try? Data(contentsOf: directory.appendingPathComponent(filename)) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func write() throws {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.group) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        try JSONEncoder().encode(self).write(to: directory.appendingPathComponent(Self.filename), options: .atomic)
    }
}
