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

enum Theme {
    static let bg = Color(hex: 0x12101C)
    static let surface = Color(hex: 0x1A1630)
    static let surfaceRaised = Color(hex: 0x1F1B36)
    static let cardFace = Color(hex: 0x221C3D)
    static let border = Color(hex: 0x2A2547)
    static let borderStrong = Color(hex: 0x3A3360)
    static let text = Color(hex: 0xEDE8F7)
    static let textBright = Color(hex: 0xF6F1FF)
    static let textSoft = Color(hex: 0xC9C2DC)
    static let muted = Color(hex: 0xA69FBF)
    static let faint = Color(hex: 0x8F88A8)
    static let gold = Color(hex: 0xE8C27A)
    static let onGold = Color(hex: 0x1A1408)
    static let online = Color(hex: 0x7FD8A6)
    static let lilac = Color(hex: 0xCDB8FF)

    /// Serif display face (New York on iOS) for names and headlines.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static let eyebrow: Font = .system(size: 12, weight: .semibold)
}

struct EyebrowText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(Theme.eyebrow)
            .tracking(1.4)
            .foregroundStyle(Theme.muted)
    }
}

struct OnlineDot: View {
    var size: CGFloat = 7
    var body: some View {
        Circle().fill(Theme.online).frame(width: size, height: size)
    }
}

struct GoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.onGold)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(Theme.gold.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

struct CardSurface: ViewModifier {
    var strong = false
    func body(content: Content) -> some View {
        content
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(strong ? Theme.borderStrong : Theme.border, lineWidth: 1)
            )
    }
}

extension View {
    func cardSurface(strong: Bool = false) -> some View { modifier(CardSurface(strong: strong)) }
}
