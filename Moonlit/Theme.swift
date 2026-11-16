import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// Antique print: aged parchment, sepia ink and vermilion rubrics, after hand-coloured tarot
/// decks and celestial maps. Hairline frames and a high-contrast serif keep it spare.
/// Colour is saved for the tarot cards (see `TarotArt`).
enum Theme {
    static let bg = Color(hex: 0xEFE2C6)
    static let surface = Color(hex: 0xF6ECD6)
    static let surfaceRaised = Color(hex: 0xFAF2E0)
    static let surfaceSelected = Color(hex: 0xEBD5A8)
    static let cardFace = Color(hex: 0xF3E6C8)
    static let border = Color(hex: 0xD2BF99)
    static let borderStrong = Color(hex: 0x8A6F4A)
    static let text = Color(hex: 0x2E2117)
    static let textBright = Color(hex: 0x1E140C)
    static let textSoft = Color(hex: 0x4A3A2C)
    static let muted = Color(hex: 0x6E5C4A)
    static let faint = Color(hex: 0x8A7864)
    /// The accent. Vermilion, like a manuscript's rubrics; named `gold` from the earlier dark theme.
    static let gold = Color(hex: 0xAE3A24)
    static let onGold = Color(hex: 0xFBF1DC)
    static let online = Color(hex: 0x4E7A4A)
    /// Second accent for small lines of colour (moods, typing dots): a dusty lapis.
    static let lilac = Color(hex: 0x3F5E8C)

    /// Corner radius of tiles, sheets and bubbles: nearly square, like a framed panel.
    static let radius: CGFloat = 6
    /// Shape of buttons and chips.
    static let chip = RoundedRectangle(cornerRadius: 3, style: .continuous)

    /// Serif display face for names and headlines: Didot when large, Baskerville when small
    /// (Didot's hairlines disappear below about 20pt).
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        let bold = weight == .semibold || weight == .bold || weight == .heavy
        if size >= 20 { return .custom(bold ? "Didot-Bold" : "Didot", fixedSize: size) }
        return .custom(bold ? "Baskerville-SemiBold" : "Baskerville", fixedSize: size + 1)
    }

    static let eyebrow: Font = .system(size: 11, weight: .semibold)
}

struct EyebrowText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(Theme.eyebrow)
            .tracking(2.2)
            .foregroundStyle(Theme.gold.opacity(0.85))
    }
}

struct OnlineDot: View {
    var size: CGFloat = 7
    var body: some View {
        Circle().fill(Theme.online).frame(width: size, height: size)
    }
}

/// A small baroque ornament: two scrolls meeting at a lozenge, with hairlines trailing off.
struct Flourish: View {
    var width: CGFloat = 120
    var color: Color = Theme.gold

    var body: some View {
        Canvas { context, size in
            let midX = size.width / 2, midY = size.height / 2
            var lines = Path()
            for side in [-1.0, 1.0] {
                // Hairline, then a scroll curling back toward the centre.
                lines.move(to: CGPoint(x: midX + side * size.width / 2, y: midY))
                lines.addLine(to: CGPoint(x: midX + side * 26, y: midY))
                lines.addCurve(to: CGPoint(x: midX + side * 12, y: midY - 5),
                               control1: CGPoint(x: midX + side * 18, y: midY),
                               control2: CGPoint(x: midX + side * 10, y: midY + 4))
                lines.addCurve(to: CGPoint(x: midX + side * 17, y: midY - 1),
                               control1: CGPoint(x: midX + side * 13, y: midY - 9),
                               control2: CGPoint(x: midX + side * 19, y: midY - 6))
            }
            context.stroke(lines, with: .color(color.opacity(0.8)), lineWidth: 0.9)
            var lozenge = Path()
            lozenge.move(to: CGPoint(x: midX, y: midY - 4.5))
            lozenge.addLine(to: CGPoint(x: midX + 4.5, y: midY))
            lozenge.addLine(to: CGPoint(x: midX, y: midY + 4.5))
            lozenge.addLine(to: CGPoint(x: midX - 4.5, y: midY))
            lozenge.closeSubpath()
            context.fill(lozenge, with: .color(color))
        }
        .frame(width: width, height: 20)
        .accessibilityHidden(true)
    }
}

struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .textCase(.uppercase)
            .tracking(1.6)
            .foregroundStyle(Theme.onGold)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.gold.opacity(configuration.isPressed ? 0.8 : 1), in: Theme.chip)
            // A second, inset line: the frame-within-a-frame of a gilt panel.
            .overlay(Theme.chip.inset(by: 4).stroke(Theme.onGold.opacity(0.45), lineWidth: 0.75))
    }
}

struct CardSurface: ViewModifier {
    var strong = false
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Theme.radius, style: .continuous) }

    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: shape)
            .overlay(shape.stroke(strong ? Theme.borderStrong : Theme.border, lineWidth: 1))
            // Strong tiles get a double frame.
            .overlay(shape.inset(by: 4).stroke(Theme.borderStrong.opacity(strong ? 0.45 : 0), lineWidth: 0.75))
    }
}

extension View {
    func cardSurface(strong: Bool = false) -> some View { modifier(CardSurface(strong: strong)) }
}

/// The dark palette of the cosmic view, which stays a night sky whatever the rest of the app looks like.
enum NightTheme {
    static let bg = Color(hex: 0x0F0C0B)
    static let surface = Color(hex: 0x171311)
    static let surfaceRaised = Color(hex: 0x1F1916)
    static let border = Color(hex: 0x2E2620)
    static let borderStrong = Color(hex: 0x5A4A30)
    static let textBright = Color(hex: 0xFAF3E3)
    static let textSoft = Color(hex: 0xCFC4AF)
    static let muted = Color(hex: 0xA3978A)
    static let gold = Color(hex: 0xD4AF6A)
    static let onGold = Color(hex: 0x1A1206)
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font { Theme.display(size, weight) }
}
