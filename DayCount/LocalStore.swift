import Foundation

struct ReviewProgress: Codable {
    var dates: [CivilDay] = []
    var saved = false
    var shared = false
    var requestedVersion: String?

    mutating func record(_ day: CivilDay) {
        if dates.count < 3 && !dates.contains(day) { dates.append(day) }
    }

    func isReady(version: String) -> Bool {
        dates.count >= 3 && saved && shared && requestedVersion != version
    }
}

struct AppData: Codable {
    var schemaVersion = 1
    var events: [Event] = []
    var widgetID: UUID?
    var review = ReviewProgress()
}

actor LocalStore {
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("dates.json") }

    init(directory: URL) { self.directory = directory }

    func load(reset: Bool = false) throws -> AppData {
        if reset {
            do { try FileManager.default.removeItem(at: file) }
            catch let failure as CocoaError where failure.code == .fileNoSuchFile { }
        }
        let decoded: AppData
        do {
            decoded = try JSONDecoder().decode(AppData.self, from: Data(contentsOf: file))
        } catch let failure as CocoaError where failure.code == .fileReadNoSuchFile {
            return AppData()
        }
        guard decoded.schemaVersion == 1, Set(decoded.events.map(\.id)).count == decoded.events.count,
              decoded.events.allSatisfy({ $0.card.isValid }) else { throw DateCardError.invalid }
        return decoded
    }

    func save(_ data: AppData) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(data).write(to: file, options: .atomic)
    }

    func syncWidget(_ data: AppData, previewDay: CivilDay?) throws {
        try WidgetSnapshot(events: data.events, selected: data.widgetID, previewDay: previewDay).write()
    }
}
