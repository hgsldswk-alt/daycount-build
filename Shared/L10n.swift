import Foundation

enum L {
    static func t(_ key: String) -> String { NSLocalizedString(key, comment: "") }
    static func f(_ key: String, _ args: CVarArg...) -> String { String(format: t(key), locale: Locale.current, arguments: args) }
    enum DateStyle { case full, shortWeekday, short, plain, month, compact }

    static func date(_ day: CivilDay, _ style: DateStyle) -> String {
        let calendar = CivilDay.utc
        guard let value = day.date(in: calendar, hour: 12) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        switch style {
        case .full: formatter.setLocalizedDateFormatFromTemplate("yMMMMdEEE")
        case .shortWeekday: formatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        case .short: formatter.setLocalizedDateFormatFromTemplate("MMMd")
        case .plain: formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        case .month: formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        case .compact: formatter.setLocalizedDateFormatFromTemplate("yMd")
        }
        return formatter.string(from: value)
    }
}
