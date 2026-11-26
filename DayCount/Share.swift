import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

enum ShareError: Error { case image }

enum ShareImage {
    static func storeURL(id: String?) -> URL {
        if let id, !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) {
            return URL(string: "https://apps.apple.com/app/id" + id)!
        }
        return URL(string: "https://example.invalid/daycount")!
    }

    static let appStoreID = Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String
    static var downloadURL: URL { storeURL(id: appStoreID) }

    static func qr(url: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let raw = filter.outputImage else { return nil }
        let bounds = raw.extent.insetBy(dx: -4, dy: -4)
        let quiet = raw.composited(over: CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: bounds))
            .transformed(by: CGAffineTransform(scaleX: 6, y: 6))
        return CIContext().createCGImage(quiet, from: quiet.extent)
    }

    @MainActor
    static func render(event: Event, today: CivilDay, url: URL) throws -> UIImage {
        guard let qr = qr(url: url) else { throw ShareError.image }
        let renderer = ImageRenderer(content: ShareArtwork(event: event, today: today, qr: qr,
                                                           placeholder: url.host == "example.invalid"))
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { throw ShareError.image }
        return image
    }
}

private struct ShareArtwork: View {
    let event: Event
    let today: CivilDay
    let qr: CGImage
    let placeholder: Bool

    var body: some View {
        let reading = DayReading(kind: event.kind, target: event.day, today: today)
        VStack(alignment: .leading, spacing: 12) {
            Text(event.day.formatted(.plain)).font(.subheadline).opacity(0.9)
            Group {
                Text(event.title).font(.system(size: 34, weight: .bold))
                    .lineLimit(3).minimumScaleFactor(0.4)
                if let milestone = reading.milestone(kind: event.kind) {
                    Text(milestone).font(.system(size: 52, weight: .bold)).lineLimit(2).minimumScaleFactor(0.45)
                } else {
                    Text(reading.prefix).font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(reading.days.formatted()).font(.system(size: 106, weight: .bold))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.32)
                        Text(reading.unit).font(.title3.weight(.semibold))
                    }
                }
            }
            Spacer(minLength: 3)
            Rectangle().fill(.white.opacity(0.4)).frame(height: 1)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L.t("share.hashtag")).font(.subheadline.weight(.semibold))
                    Text(L.f("share.generated", today.formatted(.compact))).font(.caption).opacity(0.9)
                }
                Spacer()
                VStack(spacing: 4) {
                    Image(decorative: qr, scale: 1).interpolation(.none)
                        .resizable().frame(width: CGFloat(qr.width) / 3, height: CGFloat(qr.height) / 3)
                    Text(L.t(placeholder ? "share.qr-placeholder" : "share.qr")).font(.system(size: 9))
                }
            }
        }
        .foregroundStyle(.white)
        .padding(26)
        .frame(width: 360, height: 480, alignment: .topLeading)
        .background(Palette.blue)
        .environment(\.colorScheme, .light)
    }
}

struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
    var directory: URL?
}

struct ActivitySheet: UIViewControllerRepresentable {
    let payload: SharePayload
    let completed: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: payload.items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, success, _, _ in
            DispatchQueue.main.async { completed(success) }
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

enum ShareFiles {
    static func writePNG(_ image: UIImage) throws -> URL {
        guard let bytes = image.pngData() else { throw ShareError.image }
        return try write(bytes, name: L.t("file.single") + ".png")
    }

    static func write(_ cards: [DateCard]) throws -> URL {
        let bytes = try DateCardCodec.encode(cards)
        return try write(bytes, name: L.t(cards.count == 1 ? "file.single" : "file.batch") + ".datecard")
    }

    private static func write(_ bytes: Data, name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DateCard-" + UUID().uuidString,
                                                                                      isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        do { try bytes.write(to: file, options: .atomic); return file }
        catch { try? FileManager.default.removeItem(at: directory); throw error }
    }

    static func read(_ file: URL) throws -> [DateCard] {
        let scoped = file.startAccessingSecurityScopedResource()
        defer { if scoped { file.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        return try DateCardCodec.decode(handle.read(upToCount: DateCardCodec.maxSize + 1) ?? Data())
    }
}
