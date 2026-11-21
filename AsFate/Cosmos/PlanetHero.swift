import SceneKit
import SwiftUI

/// A large, slowly turning close-up of one body, for the top of its detail sheet. It starts with the
/// 2K map so something shows at once, then swaps in the largest map there is (see `PlanetTextures`).
struct PlanetHero: UIViewRepresentable {
    let planet: Ephemeris.Body

    final class Coordinator {
        var planet: Ephemeris.Body?
        var loading: Task<Void, Never>?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        // Not interactive, so it never fights the sheet's scrolling.
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        guard context.coordinator.planet != planet else { return }
        context.coordinator.planet = planet
        context.coordinator.loading?.cancel()

        let (scene, material) = Self.makeScene(for: planet)
        view.scene = scene
        view.isPlaying = true

        let coordinator = context.coordinator
        let planet = planet
        coordinator.loading = Task { @MainActor in
            guard let image = await PlanetTextures.heroTexture(for: planet),
                  !Task.isCancelled, coordinator.planet == planet else { return }
            material.diffuse.contents = image
            if planet == .sun { material.emission.contents = image }
        }
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.loading?.cancel()
        view.scene = nil
    }

    /// The scene and the globe's material, so the large map can be put on it once it has loaded.
    private static func makeScene(for planet: Ephemeris.Body) -> (SCNScene, SCNMaterial) {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let camera = SCNCamera()
        camera.fieldOfView = 30
        camera.zNear = 0.1
        camera.zFar = 50
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        // Saturn needs room for its rings.
        cameraNode.position = SCNVector3(0, 0, planet == .saturn ? 6.6 : (planet == .uranus ? 6.9 : 4.3))
        scene.rootNode.addChildNode(cameraNode)

        // Sunlight from the upper left, with a little fill so the night side isn't black.
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .omni
        sun.light?.intensity = 1500
        sun.position = SCNVector3(-7, 4, 7)
        scene.rootNode.addChildNode(sun)
        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 140
        scene.rootNode.addChildNode(fill)

        let sphere = SCNSphere(radius: 1)
        sphere.segmentCount = 192
        let material = SCNMaterial()
        let small = PlanetTextures.texture(for: planet)
        material.diffuse.contents = small
        material.diffuse.mipFilter = .linear
        material.diffuse.maxAnisotropy = 16
        if planet == .sun {
            // The Sun lights itself.
            material.lightingModel = .constant
            material.emission.contents = small
        } else {
            material.lightingModel = .lambert
        }
        if planet == .uranus {
            // The only map of Uranus is close to a flat colour, so add what the eye expects of an ice
            // giant: faint cloud bands along its latitudes and a paler haze over the poles.
            material.shaderModifiers = [.surface: """
            float v = _surface.diffuseTexcoord.y;
            float bands = sin(v * 44.0) * 0.5 + sin(v * 17.0 + 1.3) * 0.35 + sin(v * 91.0 + 0.7) * 0.15;
            float pole = smoothstep(0.0, 0.24, v) * smoothstep(1.0, 0.76, v);
            _surface.diffuse.rgb *= (1.0 + bands * 0.11) * mix(1.18, 0.95, pole);
            """]
        }
        sphere.materials = [material]

        let globe = SCNNode(geometry: sphere)
        let tilt = SCNNode()
        tilt.eulerAngles = SCNVector3(0.18, 0, planet == .uranus ? 1.7 : 0.4)
        tilt.addChildNode(globe)
        globe.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 48)))
        // Uranus lies on its side: turned a little toward the camera, its bands and rings read as
        // ellipses instead of edge-on lines.
        let facing = SCNNode()
        facing.eulerAngles = SCNVector3(0, planet == .uranus ? -0.6 : 0, 0)
        facing.addChildNode(tilt)
        scene.rootNode.addChildNode(facing)

        if planet == .earth, let clouds = PlanetTextures.earthClouds {
            let layer = SCNSphere(radius: 1.012)
            layer.segmentCount = 128
            let cm = SCNMaterial()
            cm.lightingModel = .lambert
            cm.diffuse.contents = clouds
            cm.blendMode = .add
            cm.writesToDepthBuffer = false
            layer.materials = [cm]
            let cloudNode = SCNNode(geometry: layer)
            cloudNode.runAction(.repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 70)))
            globe.addChildNode(cloudNode)
        }

        // A thin glow at the edge for the bodies with an atmosphere.
        if [.earth, .venus, .jupiter, .saturn, .uranus, .neptune].contains(planet) {
            let rim = SCNSphere(radius: 1.045)
            rim.segmentCount = 128
            let color = UIColor(rgb: planet.colorHex)
            let am = SCNMaterial()
            am.lightingModel = .constant
            am.diffuse.contents = color.withAlphaComponent(0)
            am.emission.contents = color
            am.blendMode = .add
            am.writesToDepthBuffer = false
            am.shaderModifiers = [.fragment: """
            float rim = 1.0 - abs(dot(normalize(_surface.normal), normalize(_surface.view)));
            _output.color = vec4(_output.color.rgb * pow(rim, 2.6) * 0.9, 0.0);
            """]
            rim.materials = [am]
            scene.rootNode.addChildNode(SCNNode(geometry: rim))
        }

        if planet == .uranus {
            // Its rings circle the equator, which lies almost on its side.
            let ring = SCNNode(geometry: PlanetTextures.saturnRingGeometry(inner: 1.38, outer: 1.78,
                                                                           contents: PlanetTextures.uranusRings))
            tilt.addChildNode(ring)
        }

        if planet == .saturn {
            let ring = SCNNode(geometry: PlanetTextures.saturnRingGeometry(inner: 1.25, outer: 2.3,
                                                                           texture: "8k_saturn_ring_alpha.png"))
            ring.eulerAngles = SCNVector3(0.42, 0, 0.12)
            scene.rootNode.addChildNode(ring)
        }
        return (scene, material)
    }
}
