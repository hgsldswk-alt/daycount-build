import Foundation

struct DateCard: Codable, Equatable {
    static let titleLimit = 80
    let title: String
    let kind: EventKind
    let day: CivilDay

    var normalizedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isValid: Bool {
        !normalizedTitle.isEmpty && title.count <= Self.titleLimit && title.utf8.count <= 1024
            && !title.unicodeScalars.contains { scalar in
                [.control, .lineSeparator, .paragraphSeparator].contains(scalar.properties.generalCategory)
            } && day.isValid
    }
    var duplicateKey: Key {
        let words = normalizedTitle.split(whereSeparator: \.isWhitespace)
        let name = words.joined(separator: " ").precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return Key(title: name, kind: kind, day: day)
    }

    struct Key: Hashable {
        let title: String
        let kind: EventKind
        let day: CivilDay
    }
}

enum DateCardError: Error { case invalid, version, limit }

enum DateCardCodec {
    static let maxSize = 1_048_576
    static let maxCount = 5000
    static let prefix = "DATECARD1."
    private struct Envelope: Codable {
        let schemaVersion: Int
        let cards: [DateCard]
    }
    private struct Version: Decodable { let schemaVersion: Int }

    static func encode(_ cards: [DateCard]) throws -> Data {
        try validate(cards)
        let data = try JSONEncoder().encode(Envelope(schemaVersion: 1, cards: cards))
        guard data.count <= maxSize else { throw DateCardError.limit }
        return data
    }

    static func decode(_ data: Data) throws -> [DateCard] {
        guard data.count <= maxSize else { throw DateCardError.limit }
        let decoder = JSONDecoder()
        guard let version = try? decoder.decode(Version.self, from: data) else { throw DateCardError.invalid }
        guard version.schemaVersion == 1 else { throw DateCardError.version }
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { throw DateCardError.invalid }
        try validate(envelope.cards)
        return envelope.cards
    }

    static func code(_ card: DateCard) throws -> String {
        prefix + (try encode([card])).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decodeCode(_ input: String) throws -> [DateCard] {
        let code = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard code.utf8.count <= 4096 else { throw DateCardError.limit }
        guard code.hasPrefix(prefix) else {
            throw code.hasPrefix("DATECARD") ? DateCardError.version : DateCardError.invalid
        }
        let body = String(code.dropFirst(prefix.count))
        guard !body.isEmpty, body.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            throw DateCardError.invalid
        }
        let padding = String(repeating: "=", count: (4 - body.count % 4) % 4)
        guard let data = Data(base64Encoded: body.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/") + padding) else { throw DateCardError.invalid }
        let cards = try decode(data)
        guard cards.count == 1 else { throw DateCardError.invalid }
        return cards
    }

    private static func validate(_ cards: [DateCard]) throws {
        guard cards.count <= maxCount else { throw DateCardError.limit }
        guard !cards.isEmpty, cards.allSatisfy(\.isValid) else { throw DateCardError.invalid }
    }

    static func additions(_ cards: [DateCard], to events: [Event], at now: Date) -> [Event] {
        var keys = Set(events.map { $0.card.duplicateKey })
        return cards.compactMap { card in
            guard keys.insert(card.duplicateKey).inserted else { return nil }
            return Event(title: card.normalizedTitle, kind: card.kind, day: card.day, createdAt: now, modifiedAt: now)
        }
    }
}
