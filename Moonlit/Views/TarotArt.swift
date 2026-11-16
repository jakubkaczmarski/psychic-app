import SwiftUI
import UIKit

/// The face of a tarot card: Pamela Colman Smith's 1910 illustration (the Rider-Waite-Smith deck,
/// public domain, scans from Wikimedia Commons) when the app has one for the card. A card without
/// a scan is drawn instead, like an antique hand-coloured print: cream stock, an ink-ruled picture
/// of sky and land in muted pigments, and the labels in the margins.
struct TarotArt: View {
    let card: TarotCard
    /// Small drawn cards drop the name and let the picture run to the bottom margin.
    var compact = false

    /// Width over height, matching the scans.
    static let aspect: CGFloat = 0.58

    var body: some View {
        Group {
            if let image = UIImage(named: Self.imageName(for: card.name)) {
                GeometryReader { geo in
                    let shape = RoundedRectangle(cornerRadius: geo.size.width * 0.05, style: .continuous)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipShape(shape)
                        .overlay(shape.stroke(TarotArt.edge, lineWidth: max(0.6, geo.size.width * 0.012)))
                }
            } else {
                drawn
            }
        }
        .aspectRatio(TarotArt.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }

    /// "The High Priestess" is `tarot_high_priestess` in the asset catalogue.
    static func imageName(for name: String) -> String {
        var slug = name.lowercased()
        if slug.hasPrefix("the ") { slug.removeFirst(4) }
        return "tarot_" + slug.replacingOccurrences(of: " ", with: "_")
    }

    private var drawn: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let palette = Self.palette(for: card.name)
            let shape = RoundedRectangle(cornerRadius: w * 0.05, style: .continuous)
            let line = max(0.6, w * 0.011)
            // The picture, inside the margins that hold the numeral and the name.
            let panel = CGRect(x: w * 0.09, y: h * 0.15,
                               width: w * 0.82, height: h * (compact ? 0.79 : 0.685))
            let horizon = panel.minY + panel.height * 0.66
            let discY = panel.minY + panel.height * 0.4
            let disc = panel.width * 0.6

            ZStack {
                shape.fill(TarotArt.stock)

                // Sky, paling to yellow at the horizon, then the land.
                Rectangle()
                    .fill(LinearGradient(stops: [.init(color: palette.sky, location: 0),
                                                 .init(color: TarotArt.dawn, location: 0.68),
                                                 .init(color: TarotArt.dawn, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: panel.width, height: panel.height)
                    .position(x: panel.midX, y: panel.midY)
                Rays(count: 24)
                    .stroke(TarotArt.ink.opacity(0.22), lineWidth: line * 0.7)
                    .frame(width: disc * 1.75, height: disc * 1.75)
                    .position(x: w / 2, y: discY)
                    .mask(Rectangle().frame(width: panel.width, height: panel.height).position(x: panel.midX, y: panel.midY))
                Hill()
                    .fill(palette.land)
                    .frame(width: panel.width, height: panel.maxY - horizon)
                    .position(x: panel.midX, y: (horizon + panel.maxY) / 2)
                Hill()
                    .stroke(TarotArt.ink.opacity(0.7), lineWidth: line * 0.8)
                    .frame(width: panel.width, height: panel.maxY - horizon)
                    .position(x: panel.midX, y: (horizon + panel.maxY) / 2)
                    .mask(Rectangle().frame(width: panel.width, height: panel.height).position(x: panel.midX, y: panel.midY))

                // The emblem: a coloured disc ruled in ink, like the sun and moon faces of old decks.
                Circle().fill(palette.disc)
                    .frame(width: disc, height: disc)
                    .position(x: w / 2, y: discY)
                Circle().stroke(TarotArt.ink, lineWidth: line * 1.2)
                    .frame(width: disc, height: disc)
                    .position(x: w / 2, y: discY)
                Image(systemName: Self.symbol(for: card.name))
                    .font(.system(size: disc * 0.5, weight: .semibold))
                    .foregroundStyle(palette.emblem)
                    .position(x: w / 2, y: discY)

                Rectangle().stroke(TarotArt.ink, lineWidth: line * 1.2)
                    .frame(width: panel.width, height: panel.height)
                    .position(x: panel.midX, y: panel.midY)

                Text(card.numeral)
                    .font(.custom("Baskerville-SemiBold", fixedSize: max(7, w * 0.115)))
                    .foregroundStyle(TarotArt.ink)
                    .position(x: w / 2, y: h * 0.083)

                if !compact {
                    Text(card.name.uppercased())
                        .font(.custom("Baskerville-SemiBold", fixedSize: max(5, w * 0.082)))
                        .tracking(w * 0.01)
                        .foregroundStyle(TarotArt.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(width: w * 0.84)
                        .position(x: w / 2, y: h * 0.915)
                }

                shape.inset(by: w * 0.035).stroke(TarotArt.ink.opacity(0.55), lineWidth: line * 0.7)
                shape.stroke(TarotArt.edge, lineWidth: line * 1.4)
            }
            .clipShape(shape)
        }
    }

    /// Aged card stock, its darker edge, printer's ink and the pale yellow where sky meets land.
    static let stock = Color(hex: 0xF1E3C2)
    static let edge = Color(hex: 0xA88F63)
    static let ink = Color(hex: 0x2B1D12)
    static let dawn = Color(hex: 0xF0E2B0)

    struct Palette {
        let sky: Color, land: Color
        /// The medallion behind the emblem, and the emblem itself.
        let disc: Color, emblem: Color
    }

    /// Muted pigments: vermilion, ochre, olive, dusty blue and mauve.
    static func palette(for name: String) -> Palette {
        func p(_ sky: UInt32, _ land: UInt32, _ disc: UInt32, _ emblem: UInt32) -> Palette {
            Palette(sky: Color(hex: sky), land: Color(hex: land), disc: Color(hex: disc), emblem: Color(hex: emblem))
        }
        let ink: UInt32 = 0x2B1D12, cream: UInt32 = 0xFBF1DC
        switch name {
        case "The Fool": return p(0x9DBBD0, 0x8E9B55, 0xE3B04B, ink)
        case "The Magician": return p(0xC9B27A, 0x9C5A3C, 0xB8402A, cream)
        case "The High Priestess": return p(0x5E7FA8, 0x4D5F7E, 0xF1E6CB, 0x35507E)
        case "The Empress": return p(0xA9C4B0, 0x6F8F4E, 0xDB9482, ink)
        case "The Lovers": return p(0xE0BFA6, 0xA9B37A, 0xB8402A, cream)
        case "Strength": return p(0xDDBE7A, 0xB86A32, 0x7A4A6E, cream)
        case "Wheel of Fortune": return p(0x8FA5C4, 0x7A5C8A, 0xE3B04B, ink)
        case "Temperance": return p(0xA8CBD0, 0x5F8A8A, 0xF1E6CB, 0xB8402A)
        case "The Star": return p(0x3F5A8C, 0x2F4468, 0xE3B04B, ink)
        case "The Moon": return p(0x6A6FA0, 0x4A4E78, 0xEFE5CE, 0x4A4E78)
        case "The Sun": return p(0xA9C8DC, 0x8E9B55, 0xE8A93A, 0xB8402A)
        case "The World": return p(0x9CC0B4, 0x4F7F6A, 0xE3B04B, ink)
        default: return p(0x9DBBD0, 0x8E9B55, 0xE3B04B, ink)
        }
    }

    static func symbol(for name: String) -> String {
        switch name {
        case "The Fool": "figure.walk"
        case "The Magician": "wand.and.stars"
        case "The High Priestess": "moon.circle"
        case "The Empress": "leaf.fill"
        case "The Lovers": "heart.fill"
        case "Strength": "flame.fill"
        case "Wheel of Fortune": "circle.dashed"
        case "Temperance": "drop.fill"
        case "The Star": "star.fill"
        case "The Moon": "moon.fill"
        case "The Sun": "sun.max.fill"
        case "The World": "globe.europe.africa.fill"
        default: "sparkle"
        }
    }
}

/// The back shared by every card: slate blue with a pale lattice, like a printed back paper.
struct TarotBack: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let shape = RoundedRectangle(cornerRadius: w * 0.05, style: .continuous)
            let line = max(0.6, w * 0.011)
            let pale = Color(hex: 0xE6DCC6)

            ZStack {
                shape.fill(TarotArt.stock)
                shape.inset(by: w * 0.05).fill(Color(hex: 0x4F5A70))
                Lattice(spacing: max(5, w * 0.13))
                    .stroke(pale.opacity(0.55), lineWidth: line * 0.7)
                    .mask(shape.inset(by: w * 0.05))
                Circle().fill(Color(hex: 0x4F5A70)).frame(width: w * 0.46, height: w * 0.46)
                Circle().stroke(pale, lineWidth: line).frame(width: w * 0.46, height: w * 0.46)
                Image(systemName: "sun.max.fill")
                    .font(.system(size: w * 0.22))
                    .foregroundStyle(pale)
                shape.inset(by: w * 0.05).stroke(TarotArt.ink.opacity(0.6), lineWidth: line)
                shape.stroke(TarotArt.edge, lineWidth: line * 1.4)
            }
            .clipShape(shape)
        }
        .aspectRatio(TarotArt.aspect, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Engraved rays: short strokes radiating from just outside the emblem.
private struct Rays: Shape {
    let count: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        for i in 0..<count {
            let a = 2 * Double.pi * Double(i) / Double(count)
            // Alternate long and short rays.
            let inner = outer * 0.6, end = outer * (i.isMultiple(of: 2) ? 1 : 0.82)
            path.move(to: CGPoint(x: center.x + cos(a) * inner, y: center.y + sin(a) * inner))
            path.addLine(to: CGPoint(x: center.x + cos(a) * end, y: center.y + sin(a) * end))
        }
        return path
    }
}

/// Rolling ground: a gentle rise across the top edge, filled down to the bottom.
private struct Hill: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.22))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12),
                      control1: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.minY - rect.height * 0.14),
                      control2: CGPoint(x: rect.minX + rect.width * 0.65, y: rect.minY + rect.height * 0.4))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A diamond lattice of diagonal lines.
private struct Lattice: Shape {
    let spacing: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x + rect.height, y: rect.height))
            path.move(to: CGPoint(x: x + rect.height, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            x += spacing
        }
        return path
    }
}
