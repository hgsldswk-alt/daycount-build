import Foundation

struct CivilDay: Codable, Hashable, Comparable {
    let year: Int
    let month: Int
    let day: Int

    init(_ year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, in calendar: Calendar = CivilDay.localCalendar()) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(parts.year ?? 1, parts.month ?? 1, parts.day ?? 1)
    }

    static func localCalendar(_ zone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = .current
        return calendar
    }

    static var utc: Calendar { localCalendar(TimeZone(secondsFromGMT: 0)!) }

    var components: DateComponents { DateComponents(year: year, month: month, day: day) }
    var ordinal: Int { year * 10000 + month * 100 + day }
    var daysInMonth: Int {
        switch month {
        case 2: return year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400)) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    func date(in calendar: Calendar, hour: Int = 0) -> Date? {
        guard isValid else { return nil }
        var parts = components
        parts.hour = hour
        guard let date = calendar.date(from: parts), CivilDay(date, in: calendar) == self else { return nil }
        return date
    }

    var isValid: Bool { (1...9999).contains(year) && (1...12).contains(month) && (1...daysInMonth).contains(day) }

    private var dayNumber: Int {
        let precedingYear = year - 1
        let daysBeforeMonth = [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
        let leapDay = month > 2 && CivilDay(year, 2, 1).daysInMonth == 29 ? 1 : 0
        return precedingYear * 365 + precedingYear / 4 - precedingYear / 100 + precedingYear / 400
            + daysBeforeMonth[month - 1] + leapDay + day
    }

    func distance(to other: Self) -> Int {
        guard isValid, other.isValid else { return 0 }
        return other.dayNumber - dayNumber
    }

    func adding(days: Int) -> Self? {
        let calendar = Self.utc
        guard let date = date(in: calendar), let next = calendar.date(byAdding: .day, value: days, to: date) else { return nil }
        let result = CivilDay(next, in: calendar)
        return result.isValid ? result : nil
    }

    func formatted(_ style: L.DateStyle = .full) -> String { L.date(self, style) }
}

enum EventKind: String, Codable, CaseIterable, Identifiable {
    case countdown, elapsed
    var id: String { rawValue }
    var label: String { L.t(self == .countdown ? "kind.countdown" : "kind.elapsed") }
}

struct Event: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var kind: EventKind
    var day: CivilDay
    var pin: Int?
    var sameDay = false
    var advance: Int?
    var createdAt = Date()
    var modifiedAt = Date()

    var card: DateCard { DateCard(title: title, kind: kind, day: day) }

    static func ordered(_ events: [Self], today: CivilDay) -> [Self] {
        events.sorted {
            if $0.pin != $1.pin { return ($0.pin ?? Int.max) < ($1.pin ?? Int.max) }
            let lhsUpcoming = $0.kind == .countdown && $0.day >= today
            let rhsUpcoming = $1.kind == .countdown && $1.day >= today
            if lhsUpcoming != rhsUpcoming { return lhsUpcoming }
            if $0.day != $1.day { return lhsUpcoming ? $0.day < $1.day : $0.day > $1.day }
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func featured(_ events: [Self], today: CivilDay) -> Self? {
        let ordered = ordered(events, today: today)
        return ordered.first { $0.pin != nil || $0.kind == .countdown && $0.day >= today }
            ?? ordered.first { $0.day <= today } ?? ordered.first
    }
}

struct DayReading: Equatable {
    enum State: Equatable { case remaining, today, passed, starts }
    let state: State
    let days: Int

    init(kind: EventKind, target: CivilDay, today: CivilDay) {
        let difference = today.distance(to: target)
        days = abs(difference)
        switch kind {
        case .countdown: state = difference == 0 ? .today : (difference > 0 ? .remaining : .passed)
        case .elapsed: state = difference > 0 ? .starts : .passed
        }
    }

    var text: String {
        switch state {
        case .remaining: return L.f(days == 1 ? "read.remaining.one" : "read.remaining", days)
        case .today: return L.t("read.today")
        case .passed: return L.f(days == 1 ? "read.passed.one" : "read.passed", days)
        case .starts: return L.f(days == 1 ? "read.starts.one" : "read.starts", days)
        }
    }

    var prefix: String {
        switch state {
        case .remaining: return L.t("read.prefix.remaining")
        case .today: return L.t("read.today")
        case .passed: return L.t("read.prefix.passed")
        case .starts: return L.t("read.prefix.starts")
        }
    }

    var unit: String {
        if state == .starts { return L.t(days == 1 ? "read.until.one" : "read.until.many") }
        return L.t(days == 1 ? "read.unit.one" : "read.unit.many")
    }

    func milestone(kind: EventKind) -> String? {
        if kind == .countdown {
            if state == .today { return text }
            if state == .remaining && days == 7 { return L.t("read.week") }
        }
        if kind == .elapsed && state == .passed && [30, 100, 365].contains(days) { return text }
        return nil
    }
}
