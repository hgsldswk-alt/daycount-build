import CoreImage
import XCTest
@testable import DayCount

final class CoreTests: XCTestCase {
    func testReadingsAndMilestones() {
        let today = CivilDay(2026, 11, 19)
        let yesterday = CivilDay(2026, 11, 18)
        let tomorrow = CivilDay(2026, 11, 20)
        let same = DayReading(kind: .countdown, target: today, today: today)
        XCTAssertEqual(same.state, .today)
        XCTAssertEqual(same.days, 0)
        XCTAssertNotNil(same.milestone(kind: .countdown))
        XCTAssertEqual(DayReading(kind: .countdown, target: yesterday, today: today).state, .passed)
        XCTAssertEqual(DayReading(kind: .countdown, target: tomorrow, today: today).state, .remaining)
        XCTAssertEqual(DayReading(kind: .elapsed, target: today, today: today).days, 0)
        XCTAssertEqual(DayReading(kind: .elapsed, target: tomorrow, today: today).state, .starts)
        for days in [30, 100, 365] {
            let milestone = DayReading(kind: .elapsed, target: today.adding(days: -days)!, today: today)
            XCTAssertEqual(milestone.days, days)
            XCTAssertNotNil(milestone.milestone(kind: .elapsed))
        }
        XCTAssertNotNil(DayReading(kind: .countdown, target: today.adding(days: 7)!, today: today).milestone(kind: .countdown))
    }

    func testCalendarYearsLeapDaysDSTAndTimeZones() throws {
        XCTAssertEqual(CivilDay(2026, 12, 31).distance(to: CivilDay(2027, 1, 1)), 1)
        XCTAssertEqual(CivilDay(2028, 2, 28).distance(to: CivilDay(2028, 3, 1)), 2)
        XCTAssertEqual(CivilDay(1900, 2, 28).distance(to: CivilDay(1900, 3, 1)), 1)
        XCTAssertFalse(CivilDay(1900, 2, 29).isValid)

        let newYork = CivilDay.localCalendar(try XCTUnwrap(TimeZone(identifier: "America/New_York")))
        for (day, hours) in [(CivilDay(2026, 3, 8), 23.0), (CivilDay(2026, 11, 1), 25.0)] {
            let start = try XCTUnwrap(day.date(in: newYork))
            let nextDay = try XCTUnwrap(day.adding(days: 1))
            let end = try XCTUnwrap(nextDay.date(in: newYork))
            XCTAssertEqual(end.timeIntervalSince(start) / 3600, hours)
            XCTAssertEqual(CivilDay(start, in: newYork).distance(to: CivilDay(end, in: newYork)), 1)
        }
        let tokyo = CivilDay.localCalendar(try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo")))
        let instant = try XCTUnwrap(CivilDay(2026, 11, 19).date(in: CivilDay.utc))
        let target = CivilDay(2026, 11, 20)
        XCTAssertEqual(CivilDay(instant, in: newYork).distance(to: target), 2)
        XCTAssertEqual(CivilDay(instant, in: tokyo).distance(to: target), 1)
        XCTAssertEqual(target, CivilDay(try XCTUnwrap(target.date(in: tokyo)), in: tokyo))
    }

    func testFeaturedOrderAndWidgetFallback() {
        let today = CivilDay(2026, 11, 19)
        let main = Event(title: "Pinned", kind: .countdown, day: CivilDay(2026, 12, 7), pin: 1)
        let near = Event(title: "Near", kind: .countdown, day: CivilDay(2026, 11, 20))
        let past = Event(title: "Past", kind: .elapsed, day: CivilDay(2026, 11, 15))
        let events = [past, near, main]
        XCTAssertEqual(Event.ordered(events, today: today).map(\.id), [main.id, near.id, past.id])
        let auto = WidgetSnapshot(events: events, selected: UUID()).card(today: today)
        XCTAssertEqual(auto?.id, Event.featured(events, today: today)?.id)
        XCTAssertEqual(auto?.reading(today: today), DayReading(kind: main.kind, target: main.day, today: today))
        XCTAssertEqual(WidgetSnapshot(events: events, selected: past.id).card(today: today)?.id, past.id)
        let automatic = WidgetSnapshot(events: [near, past], selected: nil)
        XCTAssertEqual(automatic.card(today: today)?.id, near.id)
        XCTAssertEqual(automatic.card(today: CivilDay(2026, 11, 21))?.id, near.id)
    }

    func testReminderEditRemovalPastAndZoneChange() throws {
        let utc = CivilDay.utc
        let tokyo = CivilDay.localCalendar(try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo")))
        let target = CivilDay(2026, 12, 7)
        let now = try XCTUnwrap(CivilDay(2026, 12, 1).date(in: utc))
        var event = Event(title: "Exam", kind: .countdown, day: target, sameDay: true, advance: 3)
        let first = ReminderPlan.plans(events: [event], now: now, calendar: utc)
        XCTAssertEqual(first.map(\.offset), [3, 0])
        XCTAssertEqual(first.last?.components.hour, 9)
        XCTAssertNil(first.last?.components.timeZone)
        let shifted = ReminderPlan.plans(events: [event], now: now, calendar: tokyo)
        XCTAssertEqual(first.last?.id, shifted.last?.id)
        XCTAssertEqual(try XCTUnwrap(first.last?.fireDate).timeIntervalSince(try XCTUnwrap(shifted.last?.fireDate)), 9 * 3600)

        event.day = CivilDay(2026, 12, 8)
        event.title = "New exam date"
        let updated = ReminderPlan.plans(events: [event], now: now, calendar: utc)
        XCTAssertEqual(updated.last?.id, first.last?.id)
        XCTAssertEqual(updated.last?.components.day, 8)
        XCTAssertEqual(updated.last?.title, "New exam date")
        let afterMorning = try XCTUnwrap(event.day.date(in: utc, hour: 10))
        XCTAssertTrue(ReminderPlan.plans(events: [event], now: afterMorning, calendar: utc).isEmpty)
        XCTAssertTrue(ReminderPlan.plans(events: [], now: now, calendar: utc).isEmpty)
        event.kind = .elapsed
        XCTAssertTrue(ReminderPlan.plans(events: [event], now: now, calendar: utc).isEmpty)
    }

    func testTrialStartsOnPaidOpenAndExpiresAtTheBoundary() {
        let first = Date(timeIntervalSince1970: 500_000)
        let paid = first.addingTimeInterval(900_000)
        var entitlement = Entitlement(firstOpen: first, proStartedAt: paid)
        XCTAssertEqual(entitlement.trialStart, paid)
        XCTAssertTrue(entitlement.hasPro(at: paid, free: false))
        XCTAssertTrue(entitlement.hasPro(at: entitlement.trialEnd.addingTimeInterval(-1), free: false))
        XCTAssertFalse(entitlement.hasPro(at: entitlement.trialEnd, free: false))
        entitlement.trialClaimedAt = paid.addingTimeInterval(200)
        XCTAssertEqual(entitlement.trialStart, paid, "Claiming the receipt later cannot restart the trial")
        entitlement.trialClaimedAt = paid.addingTimeInterval(-200)
        XCTAssertEqual(entitlement.trialStart, paid.addingTimeInterval(-200), "Restored receipts can preserve an older start")
        entitlement.purchasedPro = true
        XCTAssertTrue(entitlement.hasPro(at: paid.addingTimeInterval(90 * 86_400), free: false))
        XCTAssertEqual(Entitlement(firstOpen: first).trialStart, first)
    }

    func testExpiredStoragePreservesPinsRemindersAndWidgetSelection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LocalStore(directory: directory)
        let open = Date(timeIntervalSince1970: 1000)
        let trial = Entitlement(firstOpen: open)
        XCTAssertEqual(trial.pinLimit(at: open), 3)
        XCTAssertEqual(trial.pinLimit(at: trial.trialEnd), 1)
        let event = Event(title: "Exam", kind: .countdown, day: CivilDay(2026, 12, 7), pin: 2, sameDay: true, advance: 7)
        try await store.save(AppData(events: [event], widgetID: event.id))
        let saved = try await store.load()
        XCTAssertEqual(saved.events, [event])
        XCTAssertEqual(saved.widgetID, event.id)
    }

    func testDateCardRoundTripUnicodeAndNormalizedDuplicates() throws {
        let now = Date()
        let card = DateCard(title: "家族出發 👨‍👩‍👧 · Café", kind: .countdown, day: CivilDay(2026, 12, 24))
        let duplicate = DateCard(title: " 家族出發 👨‍👩‍👧  ·  CAFE\u{0301} ", kind: card.kind, day: card.day)
        let second = DateCard(title: "搬進新家", kind: .elapsed, day: CivilDay(2026, 10, 1))
        XCTAssertEqual(try DateCardCodec.decodeCode(DateCardCodec.code(card)), [card])
        XCTAssertEqual(try DateCardCodec.decode(DateCardCodec.encode([card, second])), [card, second])
        let existing = Event(title: card.title, kind: card.kind, day: card.day, pin: 1, sameDay: true)
        let additions = DateCardCodec.additions([duplicate, second, second], to: [existing], at: now)
        XCTAssertEqual(additions.map(\.card), [second])
        XCTAssertNil(additions.first?.pin)
        XCTAssertEqual(additions.first?.sameDay, false)
        XCTAssertNil(additions.first?.advance)
    }

    func testDateCardRejectionAndWriteFailure() async throws {
        XCTAssertThrowsError(try DateCardCodec.decode(Data(#"{"schemaVersion":2,"cards":[]}"#.utf8))) {
            XCTAssertEqual($0 as? DateCardError, .version)
        }
        XCTAssertThrowsError(try DateCardCodec.decode(Data("not JSON".utf8)))
        XCTAssertThrowsError(try DateCardCodec.decode(Data(count: DateCardCodec.maxSize + 1))) {
            XCTAssertEqual($0 as? DateCardError, .limit)
        }
        let bad = Data(#"{"schemaVersion":1,"cards":[{"title":"Invalid","kind":"countdown","day":{"year":2026,"month":2,"day":29}}]}"#.utf8)
        XCTAssertThrowsError(try DateCardCodec.decode(bad))
        let valid = DateCard(title: "Trip", kind: .countdown, day: CivilDay(2026, 12, 24))
        XCTAssertThrowsError(try DateCardCodec.encode(Array(repeating: valid, count: DateCardCodec.maxCount + 1)))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let bytes = Data("Existing file".utf8)
        try bytes.write(to: file)
        do {
            try await LocalStore(directory: file).save(AppData())
            XCTFail("A directory cannot replace the existing file")
        } catch {
            XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testShareQRAndRenderedDimensions() async throws {
        let storeURL = ShareImage.storeURL(id: "1234567890")
        XCTAssertEqual(storeURL.absoluteString, "https://apps.apple.com/app/id1234567890")
        XCTAssertEqual(ShareImage.storeURL(id: nil).host, "example.invalid")
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: CIContext(), options: [
            CIDetectorAccuracy: CIDetectorAccuracyHigh
        ]))
        let code = try XCTUnwrap(ShareImage.qr(url: storeURL))
        XCTAssertEqual((detector.features(in: CIImage(cgImage: code)).first as? CIQRCodeFeature)?.messageString, storeURL.absoluteString)
        let event = Event(title: "Exam", kind: .countdown, day: CivilDay(2026, 12, 7))
        let image = try await ShareImage.render(event: event, today: CivilDay(2026, 11, 19), url: storeURL)
        let cgImage = try XCTUnwrap(image.cgImage)
        XCTAssertEqual(cgImage.width, 1080)
        XCTAssertEqual(cgImage.height, 1440)
        let detected = detector.features(in: CIImage(cgImage: cgImage)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        XCTAssertTrue(detected.contains(storeURL.absoluteString))
    }

    func testReviewOnlyAfterThreeDaysSaveAndShare() {
        var progress = ReviewProgress()
        for day in [19, 19, 20, 21, 22] { progress.record(CivilDay(2026, 11, day)) }
        XCTAssertEqual(progress.dates.count, 3)
        progress.saved = true
        XCTAssertFalse(progress.isReady(version: "1"))
        progress.shared = true
        XCTAssertTrue(progress.isReady(version: "1"))
        progress.requestedVersion = "1"
        XCTAssertFalse(progress.isReady(version: "1"))
    }
}
