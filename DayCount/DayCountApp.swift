import StoreKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications

extension UTType {
    static let dateCard = UTType(exportedAs: "com.hgsldswk.daycount.datecard", conformingTo: .json)
}

struct ImportItem: Identifiable {
    let id = UUID()
    let cards: [DateCard]
    var illustration: UIImage?
}

@main
struct DayCountApp: App {
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notifications

    var body: some Scene {
        WindowGroup { RootView() }
    }
}

final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@MainActor
struct RootView: View {
    @StateObject private var model = DayModel()
    @StateObject private var purchases = Purchases()
    @Environment(\.scenePhase) private var phase
    @Environment(\.requestReview) private var requestReview

    @State private var selection: UUID?
    @State private var editor: EditorRoute?
    @State private var help = false
    @State private var paywall = false
    @State private var code = false
    @State private var importer = false
    @State private var imported: ImportItem?
    @State private var activity: SharePayload?
    @State private var shareRequested = false
    @State private var reviewTask: Task<Void, Never>?
    @State private var pendingURL: URL?
    @State private var sharing = false
    @State private var demoImage: UIImage?
    @State private var pastedCards: [DateCard]?

    private var modalOpen: Bool {
        editor != nil || help || paywall || code || importer || imported != nil || activity != nil
            || sharing || model.message != nil
    }

    var body: some View {
        content
            .foregroundStyle(Palette.ink)
            .background(Palette.paper.ignoresSafeArea())
            .tint(Palette.accent)
            .environment(\.calendar, model.calendar)
            .reviewAfterCoreAction(when: model.ready && !model.saving && !model.testing && selection == nil && !modalOpen && pendingURL == nil && pastedCards == nil, alreadyRequested: model.reviewedThisVersion) { requestReview(); Task { await model.markReviewRequested() } }
            .task {
                async let data: Void = model.start()
                async let payment: Void = purchases.start(now: model.now, testing: model.testing, expired: model.expired)
                await data
                if let pendingURL {
                    self.pendingURL = nil
                    open(pendingURL)
                } else if model.startPaywall { paywall = true }
                await payment
                queueReview()
            }
            .onChange(of: phase) { _, value in
                if value == .active {
                    Task { await model.activate(); queueReview(); await purchases.refresh() }
                } else {
                    reviewTask?.cancel()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                Task { await model.activate(); queueReview() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
                Task { await model.activate(); queueReview() }
            }
            .onChange(of: selection) { _, _ in
                shareRequested = false
                demoImage = nil
                queueReview()
            }
            .onChange(of: modalOpen) { _, _ in queueReview() }
            .onOpenURL { url in
                if model.ready { open(url) }
                else { pendingURL = url }
            }
            .sheet(item: $editor) { route in
                EventEditor(model: model, event: route.event)
            }
            .sheet(isPresented: $help) { HelpView() }
            .sheet(isPresented: $paywall) { PaywallView(purchases: purchases, now: model.currentTime) }
            .sheet(isPresented: $code, onDismiss: {
                if let cards = pastedCards {
                    pastedCards = nil
                    imported = ImportItem(cards: cards)
                }
            }) {
                CodeEntry { cards in
                    pastedCards = cards
                    code = false
                }
            }
            .sheet(item: $imported) { item in
                ImportPreview(model: model, item: item)
            }
            .sheet(item: $activity) { payload in
                ActivitySheet(payload: payload) { success in
                    activity = nil
                    if let directory = payload.directory { removeExport(directory) }
                    if success { Task { await model.completedShare(); queueReview() } }
                }
            }
            .fileImporter(isPresented: $importer, allowedContentTypes: [.dateCard]) { result in
                switch result {
                case .success(let url): importFile(url)
                case .failure: model.message = L.t("import.invalid")
                }
            }
            .alert(L.t("notice.title"), isPresented: Binding(
                get: { model.message != nil }, set: { if !$0 { model.message = nil } }
            )) {
                Button(L.t("common.ok"), role: .cancel) { model.message = nil }
            } message: {
                Text(model.message ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        if !model.ready {
            if model.loadFailed {
                VStack(spacing: 12) {
                    Text(L.t("error.read"))
                    Button(L.t("common.retry")) { Task { await model.start() } }
                        .accessibilityIdentifier("home.retry")
                }.padding()
            } else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        } else if let selection, let event = model.event(selection) {
            EventDetail(model: model, purchases: purchases, event: event, shareRequested: shareRequested,
                        back: { self.selection = nil }, edit: { editor = EditorRoute(event: event) },
                        unlock: { paywall = true }, shareImage: { requestImage(event) },
                        shareFile: { requestFiles([event.card], demoEvent: event) },
                        copy: { copyCode(event) }, copyTopic: { copyTopic() }, deleted: { self.selection = nil })
        } else {
            HomeView(model: model, purchases: purchases, open: { selection = $0 },
                     create: { editor = EditorRoute(event: nil) },
                     importCode: { code = true }, importFile: { importer = true }, help: { help = true },
                     unlock: { paywall = true }, export: { requestFiles(model.ordered.map(\.card)) },
                     review: { requestReview() }, shareRequested: shareRequested)
        }
    }

    private func open(_ url: URL) {
        if url.isFileURL { importFile(url); return }
        guard url.scheme == "daycount", url.host == "event" else { return }
        selection = UUID(uuidString: url.lastPathComponent).flatMap { model.event($0)?.id }
    }

    private func importFile(_ url: URL, illustration: UIImage? = nil) {
        Task {
            do {
                let cards = try await Task.detached(priority: .userInitiated) { try ShareFiles.read(url) }.value
                imported = ImportItem(cards: cards, illustration: illustration)
            } catch {
                model.message = importError(error)
            }
        }
    }

    private func requestImage(_ event: Event) {
        guard !sharing else { return }
        sharing = true
        shareRequested = false
        Task {
            defer { sharing = false }
            do {
                let image = try ShareImage.render(event: event, today: model.today, url: ShareImage.downloadURL)
                let file = try await Task.detached(priority: .userInitiated) { try ShareFiles.writePNG(image) }.value
                if model.storeDemo { demoImage = image }
                let directory = file.deletingLastPathComponent()
                let reading = model.dayReading(event)
                presentShare(SharePayload(
                    items: [file, L.f("share.caption", event.title, reading.text, L.t("share.hashtag"))],
                    directory: directory
                ))
                if model.testing { removeExport(directory) }
            } catch { model.message = L.t("error.share") }
        }
    }

    private func requestFiles(_ cards: [DateCard], demoEvent: Event? = nil) {
        guard !sharing else { return }
        sharing = true
        shareRequested = false
        Task {
            defer { sharing = false }
            do {
                let file = try await Task.detached(priority: .userInitiated) { try ShareFiles.write(cards) }.value
                let directory = file.deletingLastPathComponent()
                presentShare(SharePayload(items: [file, L.t("share.file-caption")], directory: directory))
                let loopback = model.testing && ProcessInfo.processInfo.arguments.contains("-loopback-file")
                if demoEvent != nil && ((model.storeDemo && demoImage != nil) || loopback) {
                    let importedCards = try await Task.detached { try ShareFiles.read(file) }.value
                    imported = ImportItem(cards: importedCards, illustration: demoImage)
                }
                if model.testing { removeExport(directory) }
            } catch { model.message = importError(error, fallback: "error.share") }
        }
    }

    private func presentShare(_ payload: SharePayload) {
        if model.testing { shareRequested = true }
        else { activity = payload }
    }

    private func removeExport(_ directory: URL) {
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: directory) }
    }

    private func copyCode(_ event: Event) {
        do {
            let code = try DateCardCodec.code(event.card)
            UIPasteboard.general.string = code
            model.message = L.t("share.copied")
        } catch { model.message = L.t("error.share") }
    }

    private func copyTopic() {
        UIPasteboard.general.string = L.t("share.hashtag")
        model.message = L.t("share.topic-copied")
    }

    private func queueReview() {
        reviewTask?.cancel()
        guard phase == .active, selection == nil, !modalOpen, !model.testing else { return }
        reviewTask = Task {
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            guard !Task.isCancelled, phase == .active, selection == nil, !modalOpen else { return }
            model.requestSharedReview { requestReview() }
        }
    }
}

func importError(_ failure: Error, fallback: String = "import.invalid") -> String {
    switch failure as? DateCardError {
    case .version: return L.t("import.version")
    case .limit: return L.t("import.limit")
    default: return L.t(fallback)
    }
}
