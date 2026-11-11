import UIKit

/// Surface textures for the planets, painted in code (equirectangular, 512×256) so the app ships no image files.
/// Each is seeded, so a planet looks the same every time.
enum PlanetTextures {
    private static var cache: [String: UIImage] = [:]

    static func texture(for body: Ephemeris.Body) -> UIImage {
        if let hit = cache[body.rawValue] { return hit }
        let image: UIImage
        switch body {
        case .sun: image = sun()
        case .mercury: image = rocky(base: 0x7E7870, dark: 0x57524C, seed: 1)
        case .venus: image = banded(colors: [0xC9A66C, 0xD6B57E, 0xB8945C, 0xD0AE74], wobble: 10, seed: 2)
        case .earth: image = earth()
        case .mars: image = mars()
        case .jupiter: image = jupiter()
        case .saturn: image = banded(colors: [0xE8D49A, 0xD9C07E, 0xF0E0B0, 0xCDB273, 0xE6D39E], wobble: 3, seed: 6)
        case .uranus: image = banded(colors: [0x9FE3E6, 0x8FD6DC, 0xA8E8EA], wobble: 1, seed: 7)
        case .neptune: image = banded(colors: [0x4F74E0, 0x3E5FCC, 0x5B82EA, 0x3A58C0], wobble: 4, seed: 8)
        case .moon: image = rocky(base: 0x9A96A0, dark: 0x6E6A74, seed: 9)
        }
        cache[body.rawValue] = image
        return image
    }

    private static let size = CGSize(width: 512, height: 256)

    private static func render(_ draw: (CGContext, inout SeededRandom) -> Void, seed: UInt64) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            var rng = SeededRandom(seed: seed)
            draw(ctx.cgContext, &rng)
        }
    }

    private static func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        UIColor(rgb: hex).withAlphaComponent(alpha).cgColor
    }

    /// Soft horizontal bands, each with a gentle wave, for the gas giants and Venus.
    private static func banded(colors: [UInt32], wobble: CGFloat, seed: UInt64) -> UIImage {
        render({ c, rng in
            c.setFillColor(color(colors[0]))
            c.fill(CGRect(origin: .zero, size: size))
            var y: CGFloat = 0
            while y < size.height {
                let h = CGFloat.random(in: 6...22, using: &rng)
                let col = colors.randomElement(using: &rng)!
                let phase = CGFloat.random(in: 0...(2 * .pi), using: &rng)
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: y))
                for x in stride(from: 0, through: size.width, by: 8) {
                    path.addLine(to: CGPoint(x: x, y: y + sin(x / 40 + phase) * wobble * 0.3))
                }
                for x in stride(from: size.width, through: 0, by: -8) {
                    path.addLine(to: CGPoint(x: x, y: y + h + sin(x / 33 + phase) * wobble * 0.3))
                }
                path.closeSubpath()
                c.addPath(path)
                c.setFillColor(color(col, 0.7))
                c.fillPath()
                y += h * 0.8
            }
            // Darker towards the poles.
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [color(0x000000, 0.35), color(0x000000, 0), color(0x000000, 0), color(0x000000, 0.35)] as CFArray,
                               locations: [0, 0.22, 0.78, 1])!
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }, seed: seed)
    }

    private static func jupiter() -> UIImage {
        let base = banded(colors: [0xD9B48A, 0xF0DCC0, 0xB98A62, 0xE8CDA8, 0xC79A70, 0xF5E6D0], wobble: 8, seed: 5)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            base.draw(at: .zero)
            // The Great Red Spot.
            let c = ctx.cgContext
            c.setFillColor(color(0xB5523A, 0.85))
            c.fillEllipse(in: CGRect(x: 300, y: 150, width: 46, height: 22))
            c.setStrokeColor(color(0xF0DCC0, 0.7))
            c.setLineWidth(2)
            c.strokeEllipse(in: CGRect(x: 297, y: 147, width: 52, height: 28))
        }
    }

    /// Grey rock with craters, for Mercury and the Moon.
    private static func rocky(base: UInt32, dark: UInt32, seed: UInt64) -> UIImage {
        render({ c, rng in
            c.setFillColor(color(base))
            c.fill(CGRect(origin: .zero, size: size))
            for _ in 0..<40 {
                let r = CGFloat.random(in: 20...70, using: &rng)
                c.setFillColor(color(dark, CGFloat.random(in: 0.1...0.3, using: &rng)))
                c.fillEllipse(in: CGRect(x: .random(in: -20...size.width, using: &rng), y: .random(in: 0...size.height, using: &rng), width: r * 1.6, height: r))
            }
            for _ in 0..<160 {
                let r = CGFloat.random(in: 2...9, using: &rng)
                let x = CGFloat.random(in: 0...size.width, using: &rng), y = CGFloat.random(in: 0...size.height, using: &rng)
                c.setFillColor(color(dark, 0.55))
                c.fillEllipse(in: CGRect(x: x, y: y, width: r * 2, height: r * 2))
                c.setFillColor(color(0xFFFFFF, 0.18))
                c.fillEllipse(in: CGRect(x: x - r * 0.25, y: y - r * 0.25, width: r * 1.5, height: r * 1.5))
            }
        }, seed: seed)
    }

    private static func blobs(_ c: CGContext, _ rng: inout SeededRandom, count: Int, color col: CGColor,
                              radius: ClosedRange<CGFloat>, yRange: ClosedRange<CGFloat>) {
        c.setFillColor(col)
        for _ in 0..<count {
            let cx = CGFloat.random(in: 0...size.width, using: &rng), cy = CGFloat.random(in: yRange, using: &rng)
            for _ in 0..<6 {
                let r = CGFloat.random(in: radius, using: &rng)
                let x = cx + .random(in: -r...r, using: &rng), y = cy + .random(in: -r * 0.6...r * 0.6, using: &rng)
                c.fillEllipse(in: CGRect(x: x - r, y: y - r * 0.7, width: r * 2, height: r * 1.4))
            }
        }
    }

    private static func earth() -> UIImage {
        render({ c, rng in
            c.setFillColor(color(0x1F5FA8))
            c.fill(CGRect(origin: .zero, size: size))
            blobs(c, &rng, count: 9, color: color(0x3F8A4A), radius: 12...30, yRange: 50...210)
            blobs(c, &rng, count: 4, color: color(0xB9A06A, 0.8), radius: 8...16, yRange: 90...170)
            // Ice caps.
            c.setFillColor(color(0xF2F6FA))
            c.fill(CGRect(x: 0, y: 0, width: size.width, height: 18))
            c.fill(CGRect(x: 0, y: size.height - 16, width: size.width, height: 16))
            // Clouds.
            for _ in 0..<60 {
                let w = CGFloat.random(in: 20...90, using: &rng)
                c.setFillColor(color(0xFFFFFF, CGFloat.random(in: 0.25...0.55, using: &rng)))
                c.fillEllipse(in: CGRect(x: .random(in: -20...size.width, using: &rng), y: .random(in: 20...236, using: &rng), width: w, height: w * 0.22))
            }
        }, seed: 3)
    }

    private static func mars() -> UIImage {
        render({ c, rng in
            c.setFillColor(color(0xC1603A))
            c.fill(CGRect(origin: .zero, size: size))
            blobs(c, &rng, count: 10, color: color(0x8A3F26, 0.55), radius: 10...28, yRange: 40...220)
            blobs(c, &rng, count: 8, color: color(0xE08A5C, 0.5), radius: 8...20, yRange: 40...220)
            c.setFillColor(color(0xF5EEE8, 0.9))
            c.fillEllipse(in: CGRect(x: -40, y: -14, width: size.width + 80, height: 30))
            c.fillEllipse(in: CGRect(x: -40, y: size.height - 18, width: size.width + 80, height: 30))
        }, seed: 4)
    }

    private static func sun() -> UIImage {
        render({ c, rng in
            c.setFillColor(color(0xFFD07A))
            c.fill(CGRect(origin: .zero, size: size))
            // Fine, low-contrast granulation; the limb darkening in the shader does the real work.
            for _ in 0..<9000 {
                let r = CGFloat.random(in: 0.8...2.4, using: &rng)
                let bright = Bool.random(using: &rng)
                c.setFillColor(color(bright ? 0xFFE7A8 : 0xF2A548, CGFloat.random(in: 0.12...0.3, using: &rng)))
                c.fillEllipse(in: CGRect(x: .random(in: 0...size.width, using: &rng), y: .random(in: 0...size.height, using: &rng), width: r * 2, height: r * 2))
            }
            // Faint brighter patches (faculae).
            for _ in 0..<30 {
                let w = CGFloat.random(in: 20...60, using: &rng)
                c.setFillColor(color(0xFFF0C0, 0.08))
                c.fillEllipse(in: CGRect(x: .random(in: 0...size.width, using: &rng), y: .random(in: 40...216, using: &rng), width: w, height: w * 0.5))
            }
            // Two small sunspots.
            for _ in 0..<2 {
                let x = CGFloat.random(in: 60...450, using: &rng), y = CGFloat.random(in: 100...160, using: &rng)
                c.setFillColor(color(0xB0601E, 0.35))
                c.fillEllipse(in: CGRect(x: x - 2, y: y - 2, width: 10, height: 8))
                c.setFillColor(color(0x5A2408, 0.55))
                c.fillEllipse(in: CGRect(x: x, y: y, width: 5, height: 4))
            }
        }, seed: 10)
    }

    /// Saturn's rings: concentric bands with the Cassini gap, transparent in the middle.
    static func saturnRings() -> UIImage {
        if let hit = cache["rings"] { return hit }
        let s = CGSize(width: 512, height: 512)
        let image = UIGraphicsImageRenderer(size: s).image { ctx in
            let c = ctx.cgContext
            var rng = SeededRandom(seed: 12)
            let center = CGPoint(x: 256, y: 256)
            // Radii as a fraction of the half-width: the planet is about 0.43.
            var r: CGFloat = 0.52
            while r < 0.98 {
                let w = CGFloat.random(in: 0.006...0.02, using: &rng)
                let gap = r > 0.78 && r < 0.81 // Cassini division
                let alpha = gap ? 0.05 : CGFloat.random(in: 0.35...0.85, using: &rng) * (r > 0.81 ? 0.7 : 1)
                let col = [0xE8D49A, 0xD9C07E, 0xF0E0B0, 0xBFA470].randomElement(using: &rng)!
                c.setStrokeColor(color(UInt32(col), alpha))
                c.setLineWidth(w * 256)
                c.strokeEllipse(in: CGRect(x: center.x - r * 256, y: center.y - r * 256, width: r * 512, height: r * 512))
                r += w
            }
        }
        cache["rings"] = image
        return image
    }

}
