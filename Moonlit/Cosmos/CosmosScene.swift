import SceneKit
import SwiftUI
import UIKit

/// The 3D cosmos: the Sun, the planets on their real orbits for the chosen date, the zodiac ring around
/// them and a starfield. Distances are compressed (logarithmic) so everything fits;
/// directions are real, so the line from Earth through a planet points at the sign it's in.
@MainActor
final class CosmosScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()
    /// The camera actually on screen (SceneKit swaps in its own after a gesture).
    weak var pointOfView: SCNNode?
    private(set) var bodyNodes: [Ephemeris.Body: SCNNode] = [:]
    private let moonNode = SCNNode()
    private let sightline = SCNNode()
    private let signHighlight = SCNNode()
    private let retroArc = SCNNode()
    private var retroKey = ""
    private var orbitNodes: [Ephemeris.Body: SCNNode] = [:]
    /// The zodiac sign the selected body is in, for the label overlay.
    private(set) var highlightedSign: Int?

    static let zodiacRadius: Float = 24
    static let fieldOfView: CGFloat = 64
    static let bandWidth: Float = 3
    private static let starRadius: Float = 90

    /// Scene distance for a real distance in AU. Logarithmic, so the inner planets get room and Neptune still fits.
    static func sceneRadius(_ au: Double) -> Float { Float(5.2 * log(1 + 1.6 * au)) }

    /// Ecliptic (x, y, z-up) to SceneKit (y-up), with the ecliptic as the floor.
    static func point(_ v: Ephemeris.Vec3, scale: Float) -> SCNVector3 {
        SCNVector3(Float(v.x) * scale, Float(v.z) * scale, Float(-v.y) * scale)
    }

    static func scenePosition(_ v: Ephemeris.Vec3) -> SCNVector3 {
        let r = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
        guard r > 0 else { return SCNVector3Zero }
        return point(v, scale: sceneRadius(r) / Float(r))
    }

    /// A point on the ecliptic at a longitude, `radius` from the centre.
    static func ecliptic(_ longitude: Double, radius: Float, height: Float = 0) -> SCNVector3 {
        let a = longitude * .pi / 180
        return SCNVector3(Float(cos(a)) * radius, height, Float(-sin(a)) * radius)
    }

    init() {
        // The real Milky Way, dimmed so planets and labels stay readable.
        if let sky = PlanetTextures.milkyWay {
            scene.background.contents = sky
            scene.background.intensity = 0.45
        } else {
            scene.background.contents = UIColor(red: 0.03, green: 0.025, blue: 0.07, alpha: 1)
        }
        scene.lightingEnvironment.intensity = 0

        let camera = SCNCamera()
        camera.zFar = 400
        camera.projectionDirection = .horizontal
        camera.fieldOfView = Self.fieldOfView
        camera.wantsHDR = true
        // Fixed exposure: auto-exposure slowly brightens the dark sky into a purple wash.
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = 0
        // Only things brighter than white (the Sun's HDR core) bloom; sunlit planets stay crisp.
        camera.bloomIntensity = 0.9
        camera.bloomThreshold = 1.1
        camera.bloomBlurRadius = 9
        camera.vignettingIntensity = 0.6
        camera.vignettingPower = 0.8
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)

        let sunLight = SCNNode()
        sunLight.light = SCNLight()
        sunLight.light?.type = .omni
        sunLight.light?.intensity = 1150
        sunLight.light?.attenuationStartDistance = 0
        sunLight.light?.attenuationEndDistance = 0
        // No distance falloff: Mercury and Venus would otherwise be blown out to white.
        sunLight.light?.attenuationFalloffExponent = 0
        scene.rootNode.addChildNode(sunLight)
        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 140
        ambient.light?.color = UIColor(red: 0.55, green: 0.5, blue: 0.9, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        buildStars()
        buildZodiacRing()
        buildSun()
        for body in Ephemeris.planets { buildPlanet(body) }
        buildMoon()

        sightline.isHidden = true
        scene.rootNode.addChildNode(sightline)
        signHighlight.isHidden = true
        scene.rootNode.addChildNode(signHighlight)
        scene.rootNode.addChildNode(retroArc)
    }

    // MARK: Building

    private func buildStars() {
        var rng = SeededRandom(seed: 7)
        var vertices: [SCNVector3] = [], colors: [SIMD4<Float>] = []
        for _ in 0..<2600 {
            // Uniform on a sphere.
            let u = Float.random(in: -1...1, using: &rng), t = Float.random(in: 0..<(2 * .pi), using: &rng)
            let s = sqrt(1 - u * u)
            let r = Self.starRadius * Float.random(in: 0.85...1, using: &rng)
            vertices.append(SCNVector3(s * cos(t) * r, u * r, s * sin(t) * r))
            let b = pow(Float.random(in: 0.15...1, using: &rng), 2.2)
            let warm = Float.random(in: 0...1, using: &rng)
            colors.append(SIMD4(b * (0.85 + 0.15 * warm), b * 0.9, b * (1 - 0.2 * warm), 1))
        }
        let starGeometry = pointCloud(vertices, colors: colors, size: 2.4)
        // Twinkle: each star's brightness drifts on its own rhythm.
        starGeometry.firstMaterial?.shaderModifiers = [.fragment: """
        float seed = fract(sin(dot(_surface.position.xy, vec2(12.9898, 78.233))) * 43758.5453);
        float tw = 0.62 + 0.38 * sin(scn_frame.time * (0.8 + seed * 2.2) + seed * 40.0);
        _output.color.rgb *= tw;
        """]
        let stars = SCNNode(geometry: starGeometry)
        stars.name = "stars"
        // A slow drift keeps the sky alive.
        stars.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 900)))
        scene.rootNode.addChildNode(stars)

        // A faint band, like the Milky Way, tilted across the sky.
        var bandV: [SCNVector3] = [], bandC: [SIMD4<Float>] = []
        for _ in 0..<2200 {
            let t = Float.random(in: 0..<(2 * .pi), using: &rng)
            let spread = Float.random(in: -1...1, using: &rng) * Float.random(in: 0...1, using: &rng) * 0.22
            let r = Self.starRadius * 0.95
            var p = SIMD3<Float>(cos(t) * r, spread * r, sin(t) * r)
            p = simd_quatf(angle: 1.05, axis: SIMD3(1, 0, 0.3)).act(p)
            bandV.append(SCNVector3(p.x, p.y, p.z))
            let b = Float.random(in: 0.08...0.3, using: &rng)
            bandC.append(SIMD4(b * 0.8, b * 0.75, b, 1))
        }
        _ = (bandV, bandC) // The photographic sky now provides the Milky Way.
    }

    private func buildZodiacRing() {
        let ring = SCNNode()
        ring.name = "zodiac"
        let inner = Self.zodiacRadius - Self.bandWidth / 2, outer = Self.zodiacRadius + Self.bandWidth / 2
        // A flat dial band with alternating segments, one per sign.
        for s in 0..<12 {
            let shade: CGFloat = s % 2 == 0 ? 0.05 : 0.022
            ring.addChildNode(bandSegment(from: Double(s) * 30, to: Double(s + 1) * 30, inner: inner, outer: outer,
                                          color: UIColor(red: 0.75, green: 0.68, blue: 1, alpha: shade)))
            ring.addChildNode(lineNode([Self.ecliptic(Double(s) * 30, radius: inner), Self.ecliptic(Double(s) * 30, radius: outer)],
                                       color: UIColor(white: 1, alpha: 0.18)))
        }
        for r in [inner, outer] {
            ring.addChildNode(lineNode((0...360).map { Self.ecliptic(Double($0), radius: r) }, color: UIColor(white: 1, alpha: 0.16)))
        }
        // Degree ticks every 5°, on the inner edge.
        for k in stride(from: 0, to: 360, by: 5) where k % 30 != 0 {
            ring.addChildNode(lineNode([Self.ecliptic(Double(k), radius: inner), Self.ecliptic(Double(k), radius: inner + 0.35)],
                                       color: UIColor(white: 1, alpha: 0.12)))
        }
        scene.rootNode.addChildNode(ring)
    }

    /// A flat ring segment on the ecliptic.
    private func bandSegment(from a: Double, to b: Double, inner: Float, outer: Float, color: UIColor) -> SCNNode {
        var v: [SCNVector3] = [], idx: [Int32] = []
        let steps = 12
        for k in 0...steps {
            let lon = a + (b - a) * Double(k) / Double(steps)
            v.append(Self.ecliptic(lon, radius: inner))
            v.append(Self.ecliptic(lon, radius: outer))
            if k < steps {
                let i = Int32(k * 2)
                idx += [i, i + 1, i + 2, i + 1, i + 3, i + 2]
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: v)], elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.isDoubleSided = true
        m.blendMode = .add
        m.writesToDepthBuffer = false
        g.materials = [m]
        return SCNNode(geometry: g)
    }

    private func buildSun() {
        let sun = SCNNode()
        sun.name = "sun"
        let sphere = SCNSphere(radius: 0.9)
        sphere.segmentCount = 72
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = PlanetTextures.texture(for: .sun)
        // Limb darkening: white-gold in the middle, deep orange at the edge, like the real Sun.
        m.shaderModifiers = [.fragment: """
        float mu = abs(dot(normalize(_surface.normal), normalize(_surface.view)));
        // HDR: the core is brighter than 1.0, so only the Sun blooms.
        // The photo already has the Sun's colour: brighten towards white-gold in the middle,
        // darken a little at the edge.
        vec3 base = _output.color.rgb;
        vec3 hot = mix(base, vec3(1.0, 0.9, 0.6), 0.45) * 1.7;
        _output.color.rgb = mix(base * 0.75, hot, pow(mu, 0.6));
        """]
        sphere.materials = [m]
        let surface = SCNNode(geometry: sphere)
        surface.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 80)))
        sun.addChildNode(surface)

        // Soft light around it: a tight warm glow and a wide faint one that breathes.
        let inner = SCNNode(geometry: SCNPlane(width: 3.2, height: 3.2))
        inner.geometry?.firstMaterial = glowMaterial(UIColor(red: 1, green: 0.84, blue: 0.55, alpha: 1))
        inner.opacity = 0.6
        inner.constraints = [SCNBillboardConstraint()]
        inner.renderingOrder = -10
        sun.addChildNode(inner)
        let outer = SCNNode(geometry: SCNPlane(width: 6, height: 6))
        outer.geometry?.firstMaterial = glowMaterial(UIColor(red: 1, green: 0.62, blue: 0.28, alpha: 1))
        outer.opacity = 0.14
        outer.constraints = [SCNBillboardConstraint()]
        outer.renderingOrder = -10
        outer.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.2, duration: 3), .fadeOpacity(to: 0.12, duration: 3)])))
        sun.addChildNode(outer)
        bodyNodes[.sun] = sun
        scene.rootNode.addChildNode(sun)
    }

    private func planetSize(_ body: Ephemeris.Body) -> CGFloat {
        switch body {
        case .jupiter: 0.95
        case .saturn: 0.8
        case .uranus, .neptune: 0.6
        case .earth, .venus: 0.48
        case .mars: 0.4
        default: 0.32
        }
    }

    private func buildPlanet(_ body: Ephemeris.Body) {
        let color = UIColor(rgb: body.colorHex)
        let node = SCNNode()
        node.name = body.rawValue

        let sphere = SCNSphere(radius: planetSize(body))
        sphere.segmentCount = 48
        let m = SCNMaterial()
        // Matte (diffuse only): no specular hotspot blowing out the day side.
        m.lightingModel = .lambert
        m.diffuse.contents = PlanetTextures.texture(for: body)
        // A little self-light so the night side isn't pitch black.
        m.emission.contents = PlanetTextures.texture(for: body)
        m.emission.intensity = 0.05
        sphere.materials = [m]
        let globe = SCNNode(geometry: sphere)
        // A slight axial tilt, then spin.
        globe.eulerAngles = SCNVector3(0, 0, body == .uranus ? 1.7 : 0.4)
        let spin = SCNNode()
        spin.addChildNode(globe)
        globe.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: body == .jupiter || body == .saturn ? 10 : 18)))
        node.addChildNode(spin)

        if body == .earth, let clouds = PlanetTextures.earthClouds {
            let layer = SCNSphere(radius: planetSize(body) * 1.015)
            layer.segmentCount = 48
            let cm = SCNMaterial()
            cm.lightingModel = .lambert
            cm.diffuse.contents = clouds
            cm.blendMode = .add
            cm.writesToDepthBuffer = false
            layer.materials = [cm]
            let cloudNode = SCNNode(geometry: layer)
            cloudNode.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 26)))
            globe.addChildNode(cloudNode)
        }

        // Atmosphere rim for the planets that have one.
        if [.earth, .venus, .uranus, .neptune, .jupiter, .saturn].contains(body) {
            let rim = SCNSphere(radius: planetSize(body) * 1.06)
            rim.segmentCount = 48
            let am = SCNMaterial()
            am.lightingModel = .constant
            am.diffuse.contents = color.withAlphaComponent(0)
            am.emission.contents = color
            am.blendMode = .add
            am.writesToDepthBuffer = false
            // Brighter at the edges (Fresnel).
            am.shaderModifiers = [.fragment: """
            float rim = 1.0 - abs(dot(normalize(_surface.normal), normalize(_surface.view)));
            _output.color = vec4(_output.color.rgb * pow(rim, 3.0) * 0.9, 0.0);
            """]
            rim.materials = [am]
            node.addChildNode(SCNNode(geometry: rim))
        }

        if body == .saturn {
            let r = Float(planetSize(body))
            let ring = SCNNode(geometry: PlanetTextures.saturnRingGeometry(inner: r * 1.25, outer: r * 2.3))
            ring.eulerAngles = SCNVector3(0.45, 0, 0.15)
            node.addChildNode(ring)
        }
        let halo = SCNNode(geometry: SCNPlane(width: planetSize(body) * 3.2, height: planetSize(body) * 3.2))
        halo.geometry?.firstMaterial = glowMaterial(color)
        halo.opacity = body == .earth ? 0.4 : 0.16
        halo.constraints = [SCNBillboardConstraint()]
        // Glows draw first, so planets in front of or behind them aren't washed out.
        halo.renderingOrder = -10
        node.addChildNode(halo)

        bodyNodes[body] = node
        scene.rootNode.addChildNode(node)
    }

    private func buildMoon() {
        let sphere = SCNSphere(radius: 0.16)
        sphere.segmentCount = 32
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = PlanetTextures.texture(for: .moon)
        m.emission.contents = PlanetTextures.texture(for: .moon)
        m.emission.intensity = 0.15
        sphere.materials = [m]
        moonNode.geometry = sphere
        moonNode.name = "moon"
        bodyNodes[.moon] = moonNode
        scene.rootNode.addChildNode(moonNode)
    }

    // MARK: Updating

    /// Moves everything to `date`. Cheap enough to call every frame while time is playing.
    func update(to date: Date, selected: Ephemeris.Body?) {
        let d = Ephemeris.daysSinceJ2000(date)
        for body in Ephemeris.planets {
            bodyNodes[body]?.position = Self.scenePosition(Ephemeris.heliocentric(body, days: d))
        }
        // The Moon sits just off Earth in its real direction.
        if let earth = bodyNodes[.earth]?.position {
            let dir = Self.ecliptic(Ephemeris.moonLongitude(days: d), radius: 0.95)
            moonNode.position = SCNVector3(earth.x + dir.x, earth.y, earth.z + dir.z)
        }
        // Orbits drift very slowly; redraw them only when far from where they were drawn.
        if orbitNodes.isEmpty || abs(d - orbitsDrawnAt) > 3650 { drawOrbits(days: d) }
        updateSightline(days: d, selected: selected)
    }

    private var orbitsDrawnAt: Double = 0

    private func drawOrbits(days d: Double) {
        orbitsDrawnAt = d
        for body in Ephemeris.planets {
            orbitNodes[body]?.removeFromParentNode()
            let pts = Ephemeris.orbit(body, days: d).map(Self.scenePosition)
            let alpha: CGFloat = body == .earth ? 0.45 : 0.22
            let node = lineNode(pts, color: UIColor(rgb: body.colorHex).withAlphaComponent(alpha))
            orbitNodes[body] = node
            scene.rootNode.addChildNode(node)
        }
    }

    /// For a selected body: a line from Earth through it out to the zodiac ring, and that sign lit up.
    private func updateSightline(days d: Double, selected: Ephemeris.Body?) {
        guard let selected, selected != .earth, let earth = bodyNodes[.earth]?.position else {
            sightline.isHidden = true
            signHighlight.isHidden = true
            highlightedSign = nil
            retroArc.isHidden = true
            retroKey = ""
            return
        }
        let lon = Ephemeris.geocentricLongitude(selected, days: d)
        let end = Self.ecliptic(lon, radius: Self.zodiacRadius - Self.bandWidth / 2)
        // A fine line of sight: bright from Earth to the planet, then fading out on its way to the dial,
        // so it never looks like a laser shooting off to infinity.
        // Distances are squashed to fit, so the true direction doesn't pass exactly through the drawn planet.
        // Run the line through the planet itself, then on to the planet's exact degree on the dial.
        let mid = bodyNodes[selected]?.position ?? earth
        let gold = SIMD4<Float>(0.91, 0.76, 0.48, 1)
        func at(_ f: Float) -> SCNVector3 { SCNVector3(mid.x + (end.x - mid.x) * f, mid.y + (end.y - mid.y) * f, mid.z + (end.z - mid.z) * f) }
        var pts: [SCNVector3] = [earth, mid]
        var alphas: [Float] = [0.35, 0.95]
        for k in 1...12 {
            let f = Float(k) / 12
            pts.append(at(f))
            alphas.append(0.95 * pow(1 - f, 1.6) + 0.12 * f)
        }
        sightline.geometry = fadingLine(pts, colors: alphas.map { gold * $0 })
        sightline.position = SCNVector3Zero
        sightline.orientation = SCNVector4(0, 0, 0, 1)
        sightline.isHidden = false

        let signIndex = Int(lon / 30) % 12
        if highlightedSign != signIndex {
            signHighlight.childNodes.forEach { $0.removeFromParentNode() }
            signHighlight.addChildNode(bandSegment(from: Double(signIndex) * 30, to: Double(signIndex + 1) * 30,
                                                   inner: Self.zodiacRadius - Self.bandWidth / 2,
                                                   outer: Self.zodiacRadius + Self.bandWidth / 2,
                                                   color: UIColor(Theme.gold).withAlphaComponent(0.16)))
        }
        // A small marker where the line meets the dial: the exact degree.
        let tickIn = Self.ecliptic(lon, radius: Self.zodiacRadius - Self.bandWidth / 2)
        let tickOut = Self.ecliptic(lon, radius: Self.zodiacRadius + Self.bandWidth / 2)
        signHighlight.geometry = lineGeometry([tickIn, tickOut], color: UIColor(Theme.gold).withAlphaComponent(0.9))
        signHighlight.isHidden = false
        updateRetroArc(selected, days: d)
        highlightedSign = signIndex
    }

    /// A coral arc on the inside of the dial over the stretch of zodiac the planet walks back over.
    private func updateRetroArc(_ body: Ephemeris.Body, days d: Double) {
        let key = "\(body.rawValue)-\(Int(d.rounded(.down)))"
        guard key != retroKey else { return }
        retroKey = key
        retroArc.childNodes.forEach { $0.removeFromParentNode() }
        guard let period = Ephemeris.retrogradePeriod(body, near: d) else { retroArc.isHidden = true; return }
        let from = Ephemeris.geocentricLongitude(body, days: period.end)   // where it stops going back
        var to = Ephemeris.geocentricLongitude(body, days: period.start)   // where it turned
        if to < from { to += 360 }
        let r = Self.zodiacRadius - Self.bandWidth / 2 - 0.45
        let steps = max(Int((to - from) * 2), 2)
        let pts = (0...steps).map { Self.ecliptic(from + (to - from) * Double($0) / Double(steps), radius: r) }
        let coral = UIColor(rgb: 0xF0A27A)
        let active = d >= period.start && d <= period.end
        retroArc.addChildNode(lineNode(pts, color: coral.withAlphaComponent(active ? 0.95 : 0.5)))
        retroArc.addChildNode(lineNode(pts.map { SCNVector3($0.x * 0.995, $0.y, $0.z * 0.995) }, color: coral.withAlphaComponent(active ? 0.6 : 0.3)))
        for lon in [from, to] {
            retroArc.addChildNode(lineNode([Self.ecliptic(lon, radius: r - 0.35), Self.ecliptic(lon, radius: r + 0.35)], color: coral))
        }
        retroArc.isHidden = false
    }

    func clearHighlight() {
        highlightedSign = nil
    }

    // MARK: Helpers

    private func pointCloud(_ vertices: [SCNVector3], colors: [SIMD4<Float>], size: CGFloat) -> SCNGeometry {
        let source = SCNGeometrySource(vertices: vertices)
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: colors.count,
                                            usesFloatComponents: true, componentsPerVector: 4,
                                            bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        let element = SCNGeometryElement(indices: Array(0..<Int32(vertices.count)), primitiveType: .point)
        element.pointSize = size
        element.minimumPointScreenSpaceRadius = size * 0.5
        element.maximumPointScreenSpaceRadius = size * 1.4
        let g = SCNGeometry(sources: [source, colorSource], elements: [element])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor.white
        g.materials = [m]
        return g
    }

    /// A line strip whose colour (premultiplied, additive) changes along its length.
    private func fadingLine(_ points: [SCNVector3], colors: [SIMD4<Float>]) -> SCNGeometry {
        let colorData = colors.map { SIMD4<Float>($0.x, $0.y, $0.z, 1) }.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: colors.count,
                                            usesFloatComponents: true, componentsPerVector: 4,
                                            bytesPerComponent: 4, dataOffset: 0, dataStride: 16)
        var idx: [Int32] = []
        for i in 0..<(points.count - 1) { idx += [Int32(i), Int32(i + 1)] }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: points), colorSource],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .line)])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = UIColor.white
        m.blendMode = .add
        m.writesToDepthBuffer = false
        g.materials = [m]
        return g
    }

    private func lineGeometry(_ points: [SCNVector3], color: UIColor) -> SCNGeometry {
        let source = SCNGeometrySource(vertices: points)
        var idx: [Int32] = []
        for i in 0..<(points.count - 1) { idx += [Int32(i), Int32(i + 1)] }
        let g = SCNGeometry(sources: [source], elements: [SCNGeometryElement(indices: idx, primitiveType: .line)])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color
        m.writesToDepthBuffer = false
        m.blendMode = .add
        g.materials = [m]
        return g
    }

    private func lineNode(_ points: [SCNVector3], color: UIColor) -> SCNNode {
        SCNNode(geometry: lineGeometry(points, color: color))
    }

    private func glowMaterial(_ color: UIColor) -> SCNMaterial {
        let size = CGSize(width: 128, height: 128)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            // Roughly Gaussian falloff, so there's no visible edge or flat plateau.
            let colors = [0.9, 0.5, 0.2, 0.06, 0].map { color.withAlphaComponent($0).cgColor } as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.18, 0.42, 0.7, 1])!
            ctx.cgContext.drawRadialGradient(gradient, startCenter: CGPoint(x: 64, y: 64), startRadius: 0,
                                             endCenter: CGPoint(x: 64, y: 64), endRadius: 64, options: [])
        }
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.blendMode = .add
        m.writesToDepthBuffer = false
        return m
    }
}

/// Repeatable random numbers, so the starfield looks the same every time.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
