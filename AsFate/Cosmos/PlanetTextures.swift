import SceneKit
import UIKit

/// Photographic surface maps for the cosmic view (`Moonlit/Resources/Planets/`).
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

    static var earthClouds: UIImage? { image("2k_earth_clouds.jpg") }
    static var milkyWay: UIImage? { image("2k_stars_milky_way.jpg") }

    /// Saturn's rings: a flat annulus whose texture runs from the inner edge (left of the strip) to the outer edge.
    static func saturnRingGeometry(inner: Float, outer: Float) -> SCNGeometry {
        let segments = 128
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
        m.lightingModel = .lambert
        m.diffuse.contents = image("2k_saturn_ring_alpha.png") ?? UIColor(rgb: 0xE8D49A).withAlphaComponent(0.5)
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.transparencyMode = .aOne
        g.materials = [m]
        return g
    }
}
