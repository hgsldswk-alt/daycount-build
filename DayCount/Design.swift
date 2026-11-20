import SwiftUI
import UIKit

enum Palette {
    static let blue = Color(red: 32 / 255, green: 57 / 255, blue: 184 / 255)
    static let paper = adaptive(light: 0xf8f8f3, dark: 0x161923)
    static let ink = adaptive(light: 0x191c26, dark: 0xf4f4f7)
    static let muted = adaptive(light: 0x505969, dark: 0xb4bbcf)
    static let line = adaptive(light: 0xdedfd8, dark: 0x394154)
    static let pale = adaptive(light: 0xe8edff, dark: 0x222d50)
    static let accent = adaptive(light: 0x2039b8, dark: 0xbbc8ff)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: Double((rgb >> 16) & 255) / 255,
                           green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255, alpha: 1)
        })
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(maxWidth: compact ? nil : .infinity, minHeight: compact ? 44 : 52)
            .background(Palette.blue.opacity(configuration.isPressed ? 0.78 : 1),
                        in: RoundedRectangle(cornerRadius: compact ? 22 : 16))
    }
}

struct RoundIcon: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 17, weight: .semibold))
            .frame(width: 44, height: 44)
            .background(.background, in: Circle())
            .overlay { Circle().strokeBorder(Palette.line) }
    }
}

struct LargeReading: View {
    let reading: DayReading
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 111

    var body: some View {
        Group {
            if reading.state == .today {
                Text(reading.text).font(.largeTitle.bold()).frame(minHeight: 91, alignment: .center)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(reading.days.formatted())
                        .font(.system(size: min(size, 155), weight: .bold)).monospacedDigit()
                        .tracking(-4).lineLimit(1).minimumScaleFactor(0.3)
                    Text(reading.unit).font(.title3.weight(.semibold)).lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.text)
    }
}

struct ControlLabel: View {
    let title: String
    let value: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer(minLength: 4)
            if let value { Text(value).font(.caption).foregroundStyle(Palette.muted).multilineTextAlignment(.trailing) }
            Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(Palette.muted)
        }
        .padding(.vertical, 6)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}
