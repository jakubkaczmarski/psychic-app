import SceneKit
import UIKit

/// Photographic surface maps for the cosmic view (`AsFate/Resources/Planets/`).
///
/// The solar system scene uses the 2K maps: its planets are small on screen and ten 8K maps would
/// not fit in memory. The close-up of the selected planet (`PlanetHero`) loads one large map at a time.
///
/// Textures: Solar System Scope (solarsystemscope.com/textures), based on NASA imagery,
/// licensed CC BY 4.0. The credit is shown in Settings.
enum PlanetTextures {
    private static var cache: [String: UIImage] = [:]

    private static func image(_ name: String) -> UIImage? {
        if let hit = cache[name] { return hit }
        guard let url = Bundle.main.url(forResource: name, withExtension: nil),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache[name] = image
        return image
    }

    /// The surface map for a body, or its flat colour if the file is missing.
    static func texture(for body: Ephemeris.Body) -> Any {
        let file: String
        switch body {
        case .sun: file = "2k_sun.jpg"
        case .mercury: file = "2k_mercury.jpg"
        case .venus: file = "2k_venus_atmosphere.jpg"
        case .earth: file = "2k_earth_daymap.jpg"
        case .moon: file = "2k_moon.jpg"
        case .mars: file = "2k_mars.jpg"
        case .jupiter: file = "2k_jupiter.jpg"
        case .saturn: file = "2k_saturn.jpg"
        case .uranus: file = "2k_uranus.jpg"
        case .neptune: file = "2k_neptune.jpg"
        }
        return image(file) ?? UIColor(rgb: body.colorHex)
    }

    /// The largest map there is for a body (8K, or 4K where the source has nothing bigger), for the
    /// close-up. Uranus and Neptune only exist in 2K. Decoded off the main thread and not cached, so
    /// it's freed when the close-up goes away.
    static func heroTexture(for body: Ephemeris.Body) async -> UIImage? {
        let file: String
        switch body {
        case .sun: file = "8k_sun.jpg"
        case .mercury: file = "8k_mercury.jpg"
        case .venus: file = "4k_venus_atmosphere.jpg"
        case .earth: file = "8k_earth_daymap.jpg"
        case .moon: file = "8k_moon.jpg"
        case .mars: file = "8k_mars.jpg"
        case .jupiter: file = "8k_jupiter.jpg"
        case .saturn: file = "8k_saturn.jpg"
        case .uranus, .neptune: return nil
        }
        // An 8K map is about 180 MB once decoded with its mipmaps: phones with little memory get 4K.
        let roomy = ProcessInfo.processInfo.physicalMemory >= 6_000_000_000
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let url = Bundle.main.url(forResource: file, withExtension: nil),
                  let image = UIImage(contentsOfFile: url.path) else { return nil }
            if !roomy, image.size.width > 4096 {
                return await image.byPreparingThumbnail(ofSize: CGSize(width: 4096, height: 2048))
            }
            return await image.byPreparingForDisplay()
        }.value
    }

    static var earthClouds: UIImage? { image("2k_earth_clouds.jpg") }
    static var milkyWay: UIImage? { image("2k_stars_milky_way.jpg") }

    /// Saturn's rings: a flat annulus whose texture runs from the inner edge (left of the strip) to the outer edge.
    /// Uranus's rings: a few narrow, dim bands. Drawn here because there's no photographic map of them.
    static let uranusRings: UIImage = {
        let size = CGSize(width: 512, height: 32)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            // Position across the ring system (0 inner, 1 outer), width in pixels, brightness.
            let bands: [(CGFloat, CGFloat, CGFloat)] = [(0.1, 14, 0.3), (0.3, 16, 0.36), (0.5, 14, 0.32), (0.7, 16, 0.38), (0.92, 34, 0.7)]
            for (at, width, alpha) in bands {
                UIColor(red: 0.78, green: 0.9, blue: 0.95, alpha: alpha).setFill()
                ctx.fill(CGRect(x: at * size.width - width / 2, y: 0, width: width, height: size.height))
            }
        }
    }()

    static func saturnRingGeometry(inner: Float, outer: Float, texture: String = "2k_saturn_ring_alpha.png",
                                   contents: Any? = nil) -> SCNGeometry {
        let segments = 192
        var vertices: [SCNVector3] = [], uvs: [CGPoint] = [], normals: [SCNVector3] = [], indices: [Int32] = []
        for k in 0...segments {
            let a = Float(k) / Float(segments) * 2 * .pi
            let c = cos(a), s = sin(a)
            vertices += [SCNVector3(c * inner, 0, s * inner), SCNVector3(c * outer, 0, s * outer)]
            let v = CGFloat(k) / CGFloat(segments)
            uvs += [CGPoint(x: 0, y: v), CGPoint(x: 1, y: v)]
            normals += [SCNVector3(0, 1, 0), SCNVector3(0, 1, 0)]
            if k < segments {
                let i = Int32(k * 2)
                indices += [i, i + 1, i + 2, i + 1, i + 3, i + 2]
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                                      SCNGeometrySource(textureCoordinates: uvs)],
                            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        let m = SCNMaterial()
        // Drawn rings are thin and dim already, so they aren't shaded as well.
        m.lightingModel = contents == nil ? .lambert : .constant
        m.diffuse.mipFilter = .linear
        m.diffuse.contents = contents ?? image(texture) ?? UIColor(rgb: 0xE8D49A).withAlphaComponent(0.5)
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.transparencyMode = .aOne
        g.materials = [m]
        return g
    }
}
