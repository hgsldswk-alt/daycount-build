import SwiftUI

struct CodeEntry: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var issue: String?
    let preview: ([DateCard]) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L.t("import.code-guide")).foregroundStyle(Palette.muted)
                    TextEditor(text: $text)
                        .font(.body.monospaced())
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                        .frame(minHeight: 150)
                        .accessibilityLabel(L.t("import.code")).accessibilityIdentifier("import.text")
                    PasteButton(payloadType: String.self) { values in
                        if let value = values.first {
                            text = value
                            showPreview()
                        }
                    }
                    .accessibilityIdentifier("import.paste")
                    if let issue {
                        Text(issue).foregroundStyle(.red).accessibilityIdentifier("import.error")
                    }
                    Button(L.t("import.preview"), action: showPreview)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("import.preview")
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L.t("import.code")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("common.cancel")) { dismiss() }.accessibilityIdentifier("import.cancel")
                }
            }
        }
        .task {
            if ProcessInfo.processInfo.arguments.contains("-ui-testing"),
               let supplied = ProcessInfo.processInfo.environment["DAYCOUNT_IMPORT_CODE"] {
                text = supplied
            }
        }
    }

    private func showPreview() {
        do {
            let cards = try DateCardCodec.decodeCode(text)
            issue = nil
            preview(cards)
        } catch {
            issue = importError(error)
        }
    }
}

@MainActor
struct ImportPreview: View {
    @ObservedObject var model: DayModel
    @Environment(\.dismiss) private var dismiss
    let item: ImportItem

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let illustration = item.illustration {
                        Image(uiImage: illustration).resizable().scaledToFit().frame(maxHeight: 385)
                            .frame(maxWidth: .infinity).accessibilityLabel(L.t("event.share"))
                            .accessibilityIdentifier("import.artwork")
                    }
                    if item.cards.count > 1 { Text(L.f("import.count", item.cards.count)).font(.headline) }
                    ForEach(item.cards.indices, id: \.self) { index in
                        let card = item.cards[index]
                        VStack(alignment: .leading, spacing: 5) {
                            Text(card.normalizedTitle).font(.headline)
                            Text(L.f("import.card-detail", card.kind.label, card.day.formatted(.plain)))
                                .font(.subheadline).foregroundStyle(Palette.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if index + 1 < item.cards.count { Divider() }
                    }
                    Text(L.t("import.note")).font(.footnote).foregroundStyle(Palette.muted)
                    Button(L.t("import.add")) {
                        Task { if await model.importCards(item.cards) { dismiss() } }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(model.saving).accessibilityIdentifier("import.add")
                }
                .padding(20)
            }
            .background(Palette.paper)
            .navigationTitle(L.t("import.preview")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.t("common.cancel")) { dismiss() }.accessibilityIdentifier("import.preview-cancel")
                }
            }
        }
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section(L.t("widget.name")) { Text(L.t("help.widget")) }
                Section(L.t("reminder.same-day")) { Text(L.t("help.reminders")) }
                Section(L.t("import.preview")) { Text(L.t("help.import")) }
                Section(L.t("help.privacy-title")) { Text(L.t("help.privacy")) }
            }
            .navigationTitle(L.t("home.help")).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("common.done")) { dismiss() }.accessibilityIdentifier("help.done")
                }
            }
        }
    }
}

@MainActor
struct PaywallView: View {
    @ObservedObject var purchases: Purchases
    @Environment(\.dismiss) private var dismiss
    let now: Date

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L.t("purchase.title")).font(.largeTitle.bold()).accessibilityIdentifier("paywall.title")
                    Text(summary).font(.subheadline).foregroundStyle(Palette.muted)
                        .accessibilityIdentifier("paywall.status")
                    Label(L.t("purchase.feature.pins"), systemImage: "pin")
                    Label(L.t("purchase.feature.reminders"), systemImage: "bell")
                    Label(L.t("purchase.feature.export"), systemImage: "square.and.arrow.up.on.square")
                    Text(L.t("purchase.existing")).font(.footnote).foregroundStyle(Palette.muted)
                    purchaseActions
                    if let message = purchases.message {
                        Text(message).font(.footnote).accessibilityIdentifier("paywall.message")
                    }
                }
                .padding(24)
            }
            .background(Palette.paper)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.t("common.done")) { dismiss() }.accessibilityIdentifier("paywall.done")
                }
            }
            .task { purchases.message = nil; await purchases.loadProducts() }
        }
    }

    @ViewBuilder
    private var purchaseActions: some View {
        if purchases.entitlement?.purchasedPro != true {
            if let pro = purchases.products.first(where: { $0.id == purchases.proID }) {
                Button(L.f("purchase.buy-price", pro.displayPrice)) {
                    Task { await purchases.purchase(pro) }
                }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("paywall.buy")
            } else if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
                Button(L.f("purchase.buy-price", L.t("purchase.demo-price"))) { }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("paywall.buy")
            } else {
                Button(L.t("purchase.load")) { Task { await purchases.loadProducts() } }
                    .buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("paywall.load")
            }
            if let entitlement = purchases.entitlement, entitlement.hasPro(at: now), entitlement.trialClaimedAt == nil,
               let trial = purchases.products.first(where: { $0.id == purchases.trialID }) {
                Button { Task { await purchases.purchase(trial) } } label: {
                    Text(L.t("purchase.claim")).frame(minHeight: 44).contentShape(Rectangle())
                }
                    .accessibilityIdentifier("paywall.trial")
            }
        }
        Button { Task { await purchases.restore() } } label: {
            Text(L.t("purchase.restore")).frame(minHeight: 44).contentShape(Rectangle())
        }
            .accessibilityIdentifier("paywall.restore").disabled(purchases.busy)
        Text(L.t("purchase.terms")).font(.footnote).foregroundStyle(Palette.muted)
    }

    private var summary: String {
        guard let entitlement = purchases.entitlement else { return L.t("purchase.checking") }
        if entitlement.purchasedPro { return L.t("purchase.owned") }
        if entitlement.hasPro(at: now) {
            return L.f("purchase.until", CivilDay(entitlement.trialEnd).formatted(.plain))
        }
        return L.t("purchase.expired")
    }
}
