import XCTest

final class FlowUITests: XCTestCase {
    private enum Language: String, CaseIterable {
        case hans = "zh-Hans", en, hant = "zh-Hant"

        var locale: String {
            switch self {
            case .hans: return "zh_CN"
            case .en: return "en_US"
            case .hant: return "zh_TW"
            }
        }

        var exam: String { self == .en ? "Certification Exam" : (self == .hans ? "资格考试" : "資格考試") }
        var elapsed: String { self == .en ? "Moved to a New Home" : (self == .hans ? "搬进新家" : "搬進新家") }
        var shareFile: String { self == .en ? "Share Date File" : (self == .hans ? "分享日期文件" : "分享日期檔案") }
    }

    private var app: XCUIApplication!
    private var runID = UUID()

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        runID = UUID()
    }

    private func launch(_ arguments: [String] = [], language: Language = .hans, reset: Bool = true,
                        environment: [String: String] = [:]) {
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language.rawValue))", "-AppleLocale", language.locale]
            + (reset ? ["-reset"] : []) + arguments
        app.launchEnvironment = environment.merging(["DAYCOUNT_TEST_RUN": runID.uuidString]) { _, value in value }
        app.launch()
    }

    private func tap(_ identifier: String, in scope: XCUIElement? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let button = (scope ?? app).buttons.matching(identifier: identifier).firstMatch
        if scope == nil {
            for _ in 0..<3 {
                if button.exists && button.isHittable { break }
                app.swipeUp()
            }
        }
        XCTAssertTrue(button.waitForExistence(timeout: 6), identifier, file: file, line: line)
        XCTAssertTrue(button.isHittable, identifier, file: file, line: line)
        if button.isHittable { button.tap() }
    }

    private func menuAction(_ id: String, label: String) {
        let byID = app.buttons.matching(identifier: id)
        let byLabel = app.buttons.matching(NSPredicate(format: "label == %@", label))
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if let target = (byID.allElementsBoundByIndex + byLabel.allElementsBoundByIndex).first(where: { $0.isHittable }) {
                target.tap()
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline
        XCTFail("Missing actionable menu item \(id)")
    }

    private func waitForLabel(_ label: String, on element: XCUIElement, timeout: TimeInterval = 6) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        let condition = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", label, label),
                                                   object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [condition], timeout: timeout), .completed)
    }

    private func openEvent(_ label: String) {
        let element = app.buttons.matching(identifier: "home.event").matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 6))
        element.tap()
    }

    private func create(_ name: String, day: String, elapsed: Bool = false) {
        tap("home.new")
        let field = app.textFields["editor.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText(name)
        XCTAssertFalse(app.buttons["editor.save"].isEnabled)
        if elapsed { tap("editor.kind.elapsed") }
        tap(day)
        tap("editor.save")
        XCTAssertTrue(app.buttons["home.featured"].waitForExistence(timeout: 6))
    }

    private func shot(_ name: String, screen: XCUIScreenshot? = nil) throws {
        let screenshot = screen ?? app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let path = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? ProcessInfo.processInfo.environment["TEST_RUNNER_SHOTS_DIR"] {
            do {
                let root = URL(fileURLWithPath: path, isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try screenshot.pngRepresentation.write(to: root.appendingPathComponent(name + ".png"))
            } catch {
                let note = XCTAttachment(string: "Use xcresult attachment: \(error)")
                note.lifetime = .keepAlways
                add(note)
            }
        }
    }

    func testNewCountdownEditAndTwoTapShare() {
        launch(language: .en)
        XCTAssertTrue(app.staticTexts["home.title"].waitForExistence(timeout: 6))
        XCTAssertEqual(app.alerts.count, 0)
        create("Exam", day: "day.20261120")
        waitForLabel("1 day left", on: app.buttons["home.featured"])
        tap("home.featured")
        tap("event.share")
        XCTAssertTrue(app.staticTexts["share.requested"].waitForExistence(timeout: 6))
        tap("event.more")
        menuAction("event.edit", label: "Edit Date")
        let field = app.textFields["editor.name"]
        XCTAssertTrue(field.waitForExistence(timeout: 6))
        field.tap()
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Exam".count))
        field.typeText("Trip")
        tap("editor.save")
        waitForLabel("Trip", on: app.staticTexts["event.title"])
    }

    func testElapsedWidgetSelectionAndDelete() {
        launch(language: .en)
        create("Moved", day: "day.20261118", elapsed: true)
        waitForLabel("1 day since", on: app.buttons["home.featured"])
        tap("home.featured")
        XCTAssertFalse(app.switches["reminder.toggle"].exists)
        tap("widget.select")
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Selected"),
                                                 object: app.buttons["widget.select"])
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 6), .completed)
        tap("event.more")
        menuAction("event.delete", label: "Delete Date")
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 6))
        tap("Delete Date", in: alert)
        XCTAssertTrue(app.buttons["home.new"].waitForExistence(timeout: 6))
        XCTAssertFalse(app.buttons["home.featured"].exists)
    }

    func testDeniedNotificationDoesNotBlockDate() {
        launch(["-store-demo"], language: .en, environment: ["DAYCOUNT_NOTIFICATIONS": "denied"])
        tap("home.featured")
        XCTAssertTrue(app.buttons["reminder.settings"].waitForExistence(timeout: 6))
        let toggle = app.switches["reminder.toggle"]
        XCTAssertTrue(toggle.exists)
        toggle.tap()
        XCTAssertTrue(app.buttons["event.share"].exists)
        tap("event.share")
        XCTAssertTrue(app.staticTexts["share.requested"].waitForExistence(timeout: 6))
    }

    func testTextImportUnicodeAndDuplicate() throws {
        let bytes = Data(#"{"schemaVersion":1,"cards":[{"title":"東京 🗓","kind":"countdown","day":{"year":2026,"month":12,"day":24}}]}"#.utf8)
        let code = "DATECARD1." + bytes.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        launch(language: .en, environment: ["DAYCOUNT_IMPORT_CODE": "\n" + code + "\n"])
        for index in 0..<2 {
            tap("home.more")
            menuAction("home.import-code", label: "Import Code")
            tap("import.preview")
            XCTAssertTrue(app.staticTexts["東京 🗓"].waitForExistence(timeout: 6))
            tap("import.add")
            if index == 1 {
                let alert = app.alerts.firstMatch
                XCTAssertTrue(alert.waitForExistence(timeout: 6))
                tap("OK", in: alert)
            }
            waitForLabel("東京 🗓", on: app.buttons["home.featured"])
            XCTAssertEqual(app.buttons.matching(identifier: "home.event").count, 0)
        }
    }

    func testSharedDateFileUsesImportPreview() {
        launch(["-store-demo", "-loopback-file"], language: .en)
        tap("home.featured")
        tap("event.more")
        menuAction("event.share-file", label: "Share Date File")
        tap("import.preview-cancel")
        XCTAssertTrue(app.staticTexts["share.requested"].waitForExistence(timeout: 6))
    }

    func testTrialExpiryExistingRulesAndRestore() {
        launch(["-store-demo"], language: .en)
        tap("home.more")
        menuAction("home.paywall", label: "DayCount Pro")
        waitForLabel("30-day trial", on: app.staticTexts["paywall.status"])
        tap("paywall.done")
        tap("home.featured")
        tap("reminder.advance")
        menuAction("unused", label: "3 days before")
        waitForLabel("3 days before", on: app.buttons["reminder.advance"])
        tap("event.back")
        openEvent("Hokkaido Trip")
        tap("event.more")
        menuAction("event.pin", label: "Pin Date")
        tap("event.more")
        menuAction("event.edit", label: "Edit Date")
        tap("editor.cancel")

        app.terminate()
        launch(["-expired"], language: .en, reset: false)
        tap("home.featured")
        waitForLabel("3 days before", on: app.buttons["reminder.advance"])
        tap("event.share")
        XCTAssertTrue(app.staticTexts["share.requested"].waitForExistence(timeout: 6))
        tap("event.back")
        openEvent("Hokkaido Trip")
        tap("event.more")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Unpin Date")).firstMatch.waitForExistence(timeout: 6))
        menuAction("event.pin", label: "Unpin Date")
        tap("event.back")
        tap("home.more")
        menuAction("home.export", label: "Export All Dates")
        waitForLabel("trial has ended", on: app.staticTexts["paywall.status"])
        tap("paywall.restore")
        waitForLabel("You own", on: app.staticTexts["paywall.status"])
        tap("paywall.done")
        tap("home.more")
        menuAction("home.export", label: "Export All Dates")
        XCTAssertTrue(app.staticTexts["share.requested"].waitForExistence(timeout: 6))
    }

    func testStoreScreenshots() throws {
        for language in Language.allCases {
            launch(["-store-demo"], language: language)
            let prefix = "store-\(language.rawValue)-"
            waitForLabel(language.exam, on: app.buttons["home.featured"])
            try shot(prefix + "01-home")
            tap("home.featured")
            XCTAssertTrue(app.switches["reminder.toggle"].waitForExistence(timeout: 6))
            waitForLabel("9", on: app.staticTexts["reminder.status"])
            try shot(prefix + "03-reminder")
            tap("event.back")
            openEvent(language.elapsed)
            XCTAssertTrue(app.staticTexts["event.title"].waitForExistence(timeout: 6))
            try shot(prefix + "04-elapsed")
            tap("event.back")
            tap("home.featured")
            tap("event.share")
            XCTAssertTrue(app.staticTexts["share.requested"].waitForExistence(timeout: 6))
            tap("event.more")
            menuAction("event.share-file", label: language.shareFile)
            XCTAssertTrue(app.images["import.artwork"].waitForExistence(timeout: 6))
            try shot(prefix + "05-share")
            app.terminate()
        }
    }

    func testStoreWidgetScreenshotOnConfiguredHomeScreen() throws {
        let environment = ProcessInfo.processInfo.environment
        let raw = try XCTUnwrapOrSkip(environment["DAYCOUNT_WIDGET_LANGUAGE"] ?? environment["TEST_RUNNER_DAYCOUNT_WIDGET_LANGUAGE"])
        let language = try XCTUnwrap(Language(rawValue: raw))
        launch(["-store-demo", "-widget-capture"], language: language)
        tap("home.featured")
        tap("widget.select")
        tap("event.back")
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let widget = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", language.exam, "18")).firstMatch
        XCTAssertTrue(widget.waitForExistence(timeout: 20), "Add the small DayCount widget on the simulator's first Home Screen page.")
        try shot("store-\(language.rawValue)-02-widget", screen: XCUIScreen.main.screenshot())
        widget.tap()
        waitForLabel(language.exam, on: app.staticTexts["event.title"])
    }

    func testPaidScreenshot() throws {
        launch(["-paywall"])
        XCTAssertTrue(app.staticTexts["paywall.title"].waitForExistence(timeout: 6))
        XCTAssertTrue(app.buttons["paywall.buy"].exists)
        try shot("paid-01-paywall")
    }
}

private func XCTUnwrapOrSkip(_ raw: String?) throws -> String {
    guard let raw else { throw XCTSkip("Set DAYCOUNT_WIDGET_LANGUAGE on a simulator with the real Home Screen widget installed.") }
    return raw
}
