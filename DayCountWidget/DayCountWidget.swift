import SwiftUI
import WidgetKit

private struct DayEntry: TimelineEntry {
    let date: Date
    let today: CivilDay
    let card: WidgetSnapshot.Card?
}

private struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { sample(at: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.read()
        let entry = makeEntry(at: now, snapshot: snapshot)
        completion(context.isPreview && entry.card == nil ? sample(at: now) : entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let calendar = CivilDay.localCalendar()
        let snapshot = WidgetSnapshot.read()
        let now = Date()
        let midnight = calendar.startOfDay(for: now)
        let dates = [now] + (1...7).compactMap { calendar.date(byAdding: .day, value: $0, to: midnight) }
        let entries = dates.map { makeEntry(at: $0, snapshot: snapshot, calendar: calendar) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func makeEntry(at date: Date, snapshot: WidgetSnapshot?, calendar: Calendar = CivilDay.localCalendar()) -> DayEntry {
        let day = snapshot?.previewDay ?? CivilDay(date, in: calendar)
        return DayEntry(date: date, today: day, card: snapshot?.card(today: day))
    }

    private func sample(at date: Date) -> DayEntry {
        let today = CivilDay(date)
        let event = Event(title: L.t("demo.exam"), kind: .countdown, day: today.adding(days: 18) ?? today)
        return DayEntry(date: date, today: today, card: WidgetSnapshot.Card(event))
    }
}

private struct DayWidgetView: View {
    let entry: DayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let card = entry.card {
                let reading = card.reading(today: entry.today)
                Text(card.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer(minLength: 2)
                if reading.state == .today {
                    Text(reading.text).font(.headline)
                } else {
                    Text(reading.prefix).font(.caption.weight(.semibold)).opacity(0.9)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(reading.days.formatted()).font(.system(size: 46, weight: .bold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.35)
                        Text(reading.unit).font(.caption.weight(.medium)).lineLimit(2)
                    }
                }
                Text(card.day.formatted(.short)).font(.caption).opacity(0.9)
            } else {
                Image(systemName: "calendar").font(.title)
                Spacer()
                Text(L.t("widget.empty")).font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .containerBackground(for: .widget) { Color(red: 32 / 255, green: 57 / 255, blue: 184 / 255) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.card.map {
            L.f("widget.accessibility", $0.title, $0.reading(today: entry.today).text, $0.day.formatted(.plain))
        } ?? L.t("widget.empty"))
        .widgetURL(URL(string: "daycount://event/" + (entry.card?.id.uuidString ?? "")))
    }
}

@main
struct DayCountWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.kind, provider: DayProvider()) { DayWidgetView(entry: $0) }
            .configurationDisplayName(L.t("widget.name"))
            .description(L.t("widget.description"))
            .supportedFamilies([.systemSmall])
    }
}
