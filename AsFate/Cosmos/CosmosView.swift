import SceneKit
import SpriteKit
import SwiftUI

/// Owns the 3D scene and the camera: the intro fly-in, flying to a tapped planet and following it as time moves.
@MainActor
final class CosmosController: NSObject, ObservableObject {
    let cosmos = CosmosScene()
    weak var view: SCNView?
    /// The body the camera is following; nil means the whole system.
    @Published var selected: Ephemeris.Body?

    static let overview = SCNVector3(0, 36, 31)
    /// The overview looks a little below the Sun, so the system sits above the panel.
    static let overviewAim = SCNVector3(0, 0, 5)

    private let overlay = SKScene()
    private var labels: [String: SKNode] = [:]
    private var displayLink: CADisplayLink?

    func attach(_ view: SCNView) {
        self.view = view
        overlay.scaleMode = .resizeFill
        overlay.backgroundColor = .clear
        view.overlaySKScene = overlay
        for body in Ephemeris.Body.allCases {
            labels[body.rawValue] = makeLabel(glyph: nil, name: body.name, color: .white, size: body == .sun ? 13 : (body == .moon ? 11 : 12))
        }
        for (i, sign) in ZodiacSign.all.enumerated() {
            labels["sign\(i)"] = makeLabel(glyph: sign.glyph, name: sign.name, color: UIColor(NightTheme.gold), size: 12, weight: .bold)
        }
        labels.values.forEach(overlay.addChild)
        let link = CADisplayLink(target: self, selector: #selector(placeLabels))
        link.add(to: .main, forMode: .common)
        displayLink = link
        view.scene = cosmos.scene
        view.pointOfView = cosmos.cameraNode
        cosmos.pointOfView = cosmos.cameraNode
        view.allowsCameraControl = true
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        let controller = view.defaultCameraController
        controller.interactionMode = .orbitTurntable
        controller.inertiaEnabled = true
        controller.target = SCNVector3Zero
        controller.minimumVerticalAngle = -80
        controller.maximumVerticalAngle = 80
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
    }

    /// The opening flight, while it's running: where the camera is and what it looks at, as points
    /// to glide through.
    private var intro: (start: CFTimeInterval, eyes: [SCNVector3], aims: [SCNVector3])?
    private static let introDuration: Double = 11

    /// Opens with a slow, low pass close by Saturn, Jupiter and Earth, then pulls up and back to
    /// the whole system.
    func playIntro() {
        let cam = view?.pointOfView ?? cosmos.cameraNode
        // Close enough to a planet that the usual near limit would cut into it.
        cam.camera?.zNear = 0.03
        cam.camera?.fieldOfView = CosmosScene.fieldOfView

        var eyes: [SCNVector3] = [], aims: [SCNVector3] = []
        for body in [Ephemeris.Body.saturn, .jupiter, .earth] {
            guard let p = cosmos.bodyNodes[body]?.position else { continue }
            let r = cosmos.radius(of: body)
            // Away from the Sun and off to one side: always the same side, so the path is one long arc.
            let length = max(sqrt(p.x * p.x + p.z * p.z), 0.001)
            let out = SCNVector3(p.x / length, 0, p.z / length)
            let side = SCNVector3(-out.z, 0, out.x)
            eyes.append(SCNVector3(p.x + out.x * r * 2.2 + side.x * r * 2.4,
                                   p.y + r * 0.7,
                                   p.z + out.z * r * 2.2 + side.z * r * 2.4))
            aims.append(p)
        }
        guard let first = eyes.first, let firstAim = aims.first else { return }
        // Come in from further out along the same line of sight.
        let lead = SCNVector3(first.x + (first.x - firstAim.x) * 5, first.y + 2.5, first.z + (first.z - firstAim.z) * 5)
        eyes = [lead] + eyes + [SCNVector3(Self.overview.x * 0.55, Self.overview.y * 0.45, Self.overview.z * 0.55), Self.overview]
        aims = [firstAim] + aims + [Self.overviewAim, Self.overviewAim]

        view?.allowsCameraControl = false
        cam.position = lead
        cam.look(at: firstAim, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        intro = (CACurrentMediaTime(), eyes, aims)
    }

    /// Ends the opening flight where it is, handing the camera back.
    private func stopIntro() {
        guard intro != nil else { return }
        intro = nil
        view?.allowsCameraControl = true
        view?.defaultCameraController.target = SCNVector3Zero
    }

    /// Moves the camera along the opening flight; called every frame.
    private func stepIntro() {
        guard let intro, let view else { return }
        let cam = view.pointOfView ?? cosmos.cameraNode
        let t = (CACurrentMediaTime() - intro.start) / Self.introDuration
        guard t < 1 else {
            cam.position = Self.overview
            cam.look(at: Self.overviewAim, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
            stopIntro()
            return
        }
        // Ease in and out over the whole flight, then find the stretch of the path we're on.
        let eased = t * t * (3 - 2 * t)
        let along = eased * Double(intro.eyes.count - 1)
        let i = min(Int(along), intro.eyes.count - 2)
        let f = Float(along - Double(i))
        cam.position = Self.spline(intro.eyes, i, f)
        cam.look(at: Self.spline(intro.aims, i, f), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
    }

    /// A smooth curve through the points (Catmull-Rom), between point `i` and the next.
    private static func spline(_ p: [SCNVector3], _ i: Int, _ t: Float) -> SCNVector3 {
        let a = p[max(i - 1, 0)], b = p[i], c = p[min(i + 1, p.count - 1)], d = p[min(i + 2, p.count - 1)]
        func axis(_ a: Float, _ b: Float, _ c: Float, _ d: Float) -> Float {
            0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (3 * b - a - 3 * c + d) * t * t * t)
        }
        return SCNVector3(axis(a.x, b.x, c.x, d.x), axis(a.y, b.y, c.y, d.y), axis(a.z, b.z, c.z, d.z))
    }

    func update(date: Date) {
        cosmos.update(to: date, selected: selected)
    }

    /// Camera for the dial turned so `longitude` points to the top of the screen. `zoom` < 1 moves closer.
    private func dialCamera(longitude: Double, zoom: Float) -> (eye: SCNVector3, aim: SCNVector3) {
        let a = longitude * .pi / 180
        // Toward the camera, along the ecliptic (the opposite of the sign's direction).
        let bx = Float(-cos(a)), bz = Float(sin(a))
        let eye = SCNVector3(bx * 31 * zoom, 36 * zoom, bz * 31 * zoom)
        let aim = SCNVector3Zero
        return (eye, aim)
    }

    /// Turns the dial so the selected body's sign is at the top and zooms in a little; nil goes back to the overview.
    func fly(to body: Ephemeris.Body?) {
        stopIntro()
        selected = body
        cosmos.update(to: currentDate, selected: body)
        let d = Ephemeris.daysSinceJ2000(currentDate)
        let shot: (eye: SCNVector3, aim: SCNVector3)
        if let body {
            // Earth looks toward the Sun; everything else by where it appears from Earth.
            let lon = Ephemeris.geocentricLongitude(body == .earth ? .sun : body, days: d)
            shot = dialCamera(longitude: lon, zoom: 0.97)
        } else {
            shot = (Self.overview, Self.overviewAim)
        }
        // After a gesture SceneKit drives its own copy of the camera, so move whichever one is on screen.
        let cam = view?.pointOfView ?? cosmos.cameraNode
        view?.defaultCameraController.stopInertia()
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 1.3
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0, 0, 1)
        cam.position = shot.eye
        cam.look(at: shot.aim, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        // Pinching narrows the lens instead of moving the camera; undo it so the shot frames correctly.
        cam.camera?.fieldOfView = CosmosScene.fieldOfView
        SCNTransaction.completionBlock = { [weak self] in
            self?.view?.defaultCameraController.target = SCNVector3Zero
        }
        SCNTransaction.commit()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    /// The date on screen, kept in sync by the view.
    var currentDate = Date()

    private var stays: [Ephemeris.Body: Ephemeris.SignStay] = [:]

    /// When a body entered its sign and when it leaves. Finding that means stepping through time,
    /// so the answer is kept until the body crosses into another sign.
    func stay(_ body: Ephemeris.Body, days d: Double) -> Ephemeris.SignStay {
        if let hit = stays[body], hit.sign == Ephemeris.signIndex(body, days: d),
           d >= (hit.entered ?? -.infinity), d <= (hit.leaves ?? .infinity) {
            return hit
        }
        let fresh = Ephemeris.signStay(body, days: d)
        stays[body] = fresh
        return fresh
    }

    deinit { displayLink?.invalidate() }

    private func makeLabel(glyph: String?, name: String, color: UIColor, size: CGFloat, weight: UIFont.Weight = .semibold) -> SKNode {
        let node = SKNode()
        let shadow = NSShadow()
        shadow.shadowColor = UIColor.black.withAlphaComponent(0.9)
        shadow.shadowBlurRadius = 4
        func label(_ text: String, font: UIFont, alpha: CGFloat, y: CGFloat, align: SKLabelVerticalAlignmentMode) -> SKLabelNode {
            let l = SKLabelNode()
            l.attributedText = NSAttributedString(string: text, attributes: [
                .font: font, .foregroundColor: color.withAlphaComponent(alpha), .shadow: shadow, .kern: 0.3,
            ])
            l.verticalAlignmentMode = align
            l.position = CGPoint(x: 0, y: y)
            return l
        }
        if let glyph {
            node.addChild(label(glyph, font: .systemFont(ofSize: size + 6, weight: .regular), alpha: 1, y: 1, align: .bottom))
            node.addChild(label(name.uppercased(), font: .systemFont(ofSize: size - 3, weight: weight), alpha: 0.8, y: -1, align: .top))
        } else {
            node.addChild(label(name, font: .systemFont(ofSize: size, weight: weight), alpha: 0.92, y: 0, align: .center))
        }
        return node
    }

    /// Pins the 2D labels to where each body is on screen, every frame. A label that would overlap
    /// a more important one is hidden.
    @objc private func placeLabels() {
        guard let view, view.bounds.height > 0 else { return }
        stepIntro()
        cosmos.pointOfView = view.pointOfView
        if let eye = view.pointOfView?.presentation.worldPosition { cosmos.sizeSelectionRing(cameraAt: eye, selected: selected) }
        let h = view.bounds.height
        // Where every body is drawn on screen, so labels don't land on top of another planet.
        let upVec = view.pointOfView?.presentation.worldUp ?? SCNVector3(0, 1, 0)
        let discs: [(key: String, rect: CGRect)] = Ephemeris.Body.allCases.compactMap { body in
            guard let node = cosmos.bodyNodes[body] else { return nil }
            let c = node.presentation.position, r = cosmos.radius(of: body)
            let s = view.projectPoint(c)
            guard s.z > 0, s.z < 1 else { return nil }
            let e = view.projectPoint(SCNVector3(c.x + upVec.x * r, c.y + upVec.y * r, c.z + upVec.z * r))
            let sr = CGFloat(min(hypot(e.x - s.x, e.y - s.y), 400))
            return (body.rawValue, CGRect(x: CGFloat(s.x) - sr, y: h - CGFloat(s.y) - sr, width: sr * 2, height: sr * 2))
        }
        var taken: [CGRect] = []
        /// Places a label below its point; if that spot is taken, tries right, left and above before hiding it.
        func place(_ key: String, at p: SCNVector3, offset: CGFloat, alpha: CGFloat, size: CGSize,
                   force: Bool = false, gap: CGFloat = 0) {
            guard let label = labels[key] else { return }
            let s = view.projectPoint(p)
            guard s.z > 0, s.z < 1, s.x > -60, s.x < Float(view.bounds.width) + 60 else { label.isHidden = true; return }
            let base = CGPoint(x: CGFloat(s.x), y: h - CGFloat(s.y))
            let side = gap + size.width / 2 + 4
            let candidates = [CGPoint(x: base.x, y: base.y + offset),
                              CGPoint(x: base.x + side, y: base.y),
                              CGPoint(x: base.x - side, y: base.y),
                              CGPoint(x: base.x, y: base.y - offset)]
            for pos in candidates {
                let rect = CGRect(x: pos.x - size.width / 2, y: pos.y - size.height / 2, width: size.width, height: size.height)
                let onAPlanet = discs.contains { $0.key != key && $0.rect.intersects(rect) }
                if force || (!onAPlanet && !taken.contains(where: { $0.intersects(rect) })) {
                    taken.append(rect)
                    label.isHidden = false
                    label.position = pos
                    label.alpha = alpha
                    return
                }
            }
            label.isHidden = true
        }
        // Most important first: the selected body, the Sun, Earth, then the big planets.
        var order: [Ephemeris.Body] = [.sun, .earth, .jupiter, .saturn, .mars, .venus, .mercury, .uranus, .neptune, .moon]
        if let selected, let i = order.firstIndex(of: selected) { order.remove(at: i); order.insert(selected, at: 0) }
        let up = view.pointOfView?.presentation.worldUp ?? SCNVector3(0, 1, 0)
        for body in order {
            guard let node = cosmos.bodyNodes[body] else { continue }
            let dimmed = selected != nil && selected != body && body != .earth
            let width = CGFloat(body.name.count) * 7.5 + 6
            // How big the body looks on screen, so the label sits just outside its edge at any zoom.
            let r = cosmos.radius(of: body)
            let c = node.presentation.position
            let edge = view.projectPoint(SCNVector3(c.x + up.x * r, c.y + up.y * r, c.z + up.z * r))
            let center = view.projectPoint(c)
            let screenRadius = CGFloat(min(hypot(edge.x - center.x, edge.y - center.y), 400))
            place(body.rawValue, at: c, offset: -(screenRadius + 11), alpha: (dimmed ? 0.5 : 1) * (body == .moon ? 0.8 : 1),
                  size: CGSize(width: width, height: 16), force: body == selected, gap: screenRadius)
        }
        let lit = cosmos.highlightedSign
        for i in 0..<12 {
            let p = CosmosScene.ecliptic(Double(i) * 30 + 15, radius: CosmosScene.zodiacRadius, height: 0)
            place("sign\(i)", at: p, offset: 0, alpha: lit == nil ? 0.85 : (lit == i ? 1 : 0.35),
                  size: CGSize(width: 60, height: 34), force: true)
            labels["sign\(i)"]?.setScale(lit == i ? 1.2 : 1)
        }
    }

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        guard let view else { return }
        let hits = view.hitTest(g.location(in: view), options: [.searchMode: SCNHitTestSearchMode.all.rawValue])
        for hit in hits {
            var node: SCNNode? = hit.node
            while let n = node {
                if let name = n.name, let body = Ephemeris.Body(rawValue: name) {
                    fly(to: body)
                    return
                }
                node = n.parent
            }
        }
    }
}

private struct CosmosSceneView: UIViewRepresentable {
    let controller: CosmosController
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        controller.attach(view)
        return view
    }
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

/// Colours and type of the cosmic view's sheet: a black, data-forward look with bold sans-serif
/// headings, small uppercase labels, tabular numbers and coloured status pills.
private enum Sky {
    static let sheet = Color(hex: 0x111113)
    static let tile = Color.white.opacity(0.07)
    static let line = Color.white.opacity(0.1)
    static let text = Color.white
    static let secondary = Color.white.opacity(0.58)
    static let faint = Color.white.opacity(0.34)
    static let green = Color(hex: 0x34C759)
    static let amber = Color(hex: 0xFFB340)
    static let orange = Color(hex: 0xFF8A4C)

    static func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(secondary)
    }

    static func pill(_ text: String, _ color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.6)
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
    }
}

/// White capsule button, the sheet's main action.
private struct SkyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.white.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}

extension ZodiacSign {
    /// Three letters, read like an airport code: "SCO".
    var code: String { String(name.prefix(3)).uppercased() }
}

struct CosmosView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = CosmosController()
    /// Days from now, fractional while scrubbing.
    @State private var offset: Double = 0
    @State private var playing = false
    /// Playback speed in days per second.
    @State private var speed: PlaySpeed = .day

    enum PlaySpeed: Double, CaseIterable {
        case day = 1, week = 7, month = 30
        var label: String {
            switch self {
            case .day: "1 day/s"
            case .week: "1 week/s"
            case .month: "1 month/s"
            }
        }
        var next: PlaySpeed {
            let all = Self.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }
    @State private var showHint = true
    /// The sheet pulled up to show every body as a list.
    @State private var listExpanded = false
    /// Height of the bottom sheet; the 3D view fits in the space above it so the Sun stays centred.
    @State private var panelHeight: CGFloat = 250
    /// Called with a question and context for Claude when the user asks their psychic about the sky.
    var onAsk: (String, String) -> Void = { _, _ in }

    private let now = Date()
    private var date: Date { now.addingTimeInterval(offset * 86_400) }
    private var days: Double { Ephemeris.daysSinceJ2000(date) }
    private var placements: [Ephemeris.Placement] { Ephemeris.placements(on: date) }

    /// From this width up (an unfolded iPhone Duo) the sheet becomes a panel down the right side
    /// and the solar system gets the rest of the screen.
    private static let wideWidth: CGFloat = 620
    private static let sideWidth: CGFloat = 372

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width >= Self.wideWidth
            ZStack {
                CosmosSceneView(controller: controller)
                    .padding(.bottom, wide ? 0 : max(panelHeight - 28, 0))
                    .padding(.trailing, wide ? Self.sideWidth + 12 : 0)
                    .ignoresSafeArea(edges: wide ? [.top, .bottom, .leading] : .top)
                    .animation(.spring(response: 0.45, dampingFraction: 0.9), value: panelHeight)
                    .onAppear {
                        controller.currentDate = date
                        controller.update(date: date)
                        controller.playIntro()
                    }
                    .onChange(of: offset) {
                        controller.currentDate = date
                        controller.update(date: date)
                    }

                // A soft fade at the top so the title stays readable over bright planets.
                VStack {
                    LinearGradient(colors: [.black.opacity(0.75), .black.opacity(0.35), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: wide ? 110 : 170)
                        .ignoresSafeArea(edges: .top)
                    Spacer()
                }
                .allowsHitTesting(false)

                if wide {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(spacing: 0) {
                            topBar
                            if showHint { hint.transition(.opacity) }
                            Spacer()
                        }
                        sidePanel
                            .frame(width: Self.sideWidth)
                            .padding(.vertical, 10)
                            .padding(.trailing, 10)
                    }
                } else {
                    VStack(spacing: 0) {
                        topBar
                        if showHint { hint.transition(.opacity) }
                        Spacer()
                        sheet
                    }
                }
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .task(id: playing) { await play() }
        .sensoryFeedback(.impact(weight: .medium), trigger: selectedSign)
        .task {
            try? await Task.sleep(for: .seconds(6))
            withAnimation { showHint = false }
        }
    }

    // MARK: Time

    /// While playing, time glides forward smoothly at the chosen speed (1 day a second by default).
    private func play() async {
        guard playing else { return }
        var last = Date()
        while !Task.isCancelled, playing {
            try? await Task.sleep(for: .milliseconds(16))
            let now = Date()
            offset += now.timeIntervalSince(last) * speed.rawValue
            last = now
        }
    }

    private var relativeLabel: String {
        let days = Int(offset.rounded())
        switch days {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        case 2...59: return "In \(days) days"
        case -59 ... -2: return "\(-days) days ago"
        default:
            let months = Int((Double(abs(days)) / 30.44).rounded())
            if months < 24 { return days > 0 ? "In \(months) months" : "\(months) months ago" }
            let years = Int((Double(abs(days)) / 365.25).rounded())
            return days > 0 ? "In \(years) years" : "\(years) years ago"
        }
    }

    /// A day and month, with the year when it isn't the year on screen.
    private func shortDate(_ day: Double) -> String {
        let d = Ephemeris.date(days: day)
        let f = Date.FormatStyle().day().month(.abbreviated)
        return Calendar.current.isDate(d, equalTo: date, toGranularity: .year) ? d.formatted(f) : d.formatted(f.year())
    }

    // MARK: Top

    private var topBar: some View {
        HStack {
            circleButton("xmark", label: "Close") { dismiss() }
            Spacer()
            // With the sheet pulled up the dial needs the room up here, and the sheet names the body.
            if controller.selected == nil, !listExpanded {
                VStack(spacing: 2) {
                    Text("Cosmic view").font(.system(size: 17, weight: .bold)).foregroundStyle(Sky.text)
                    Text("The solar system").font(.system(size: 12, weight: .medium)).foregroundStyle(Sky.secondary)
                }
                .transition(.opacity)
            }
            Spacer()
            circleButton("scope", label: "Show everything") { controller.fly(to: nil) }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var hint: some View {
        Text("Drag to look around · pinch to zoom · tap a planet")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Sky.secondary)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 10)
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Sky.text)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(label)
    }

    // MARK: Sheet

    private var sheet: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30, style: .continuous)
        return VStack(alignment: .leading, spacing: 14) {
            grabber
            dateHeader
            TimeRuler(offset: $offset, ticks: !playing || speed == .day, onScrubStart: { playing = false })

            if let selected = controller.selected {
                fitted(maxHeight: 430) { detail(for: selected) }
                    .transition(.opacity)
            } else if listExpanded {
                fitted(maxHeight: 330) { bodyList }
                    .transition(.opacity)
            } else {
                chips
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sky.sheet.opacity(0.94), in: shape)
        .background(.ultraThinMaterial, in: shape)
        .overlay(shape.stroke(Sky.line, lineWidth: 1))
        .background(GeometryReader { g in
            Color.clear
                .onAppear { panelHeight = g.size.height }
                .onChange(of: g.size.height) { _, h in panelHeight = h }
        })
        .ignoresSafeArea(edges: .bottom)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: controller.selected)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: listExpanded)
        .onChange(of: controller.selected) { _, new in if new != nil { listExpanded = false } }
    }

    /// The wide layout's version of the sheet: always open, with the list or the selected body's
    /// detail scrolling under the date and the time ruler.
    private var sidePanel: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        return VStack(alignment: .leading, spacing: 14) {
            dateHeader
            TimeRuler(offset: $offset, ticks: !playing || speed == .day, onScrubStart: { playing = false })
            ScrollView(showsIndicators: false) {
                if let selected = controller.selected {
                    detail(for: selected).transition(.opacity)
                } else {
                    bodyList.transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Sky.sheet.opacity(0.94), in: shape)
        .background(.ultraThinMaterial, in: shape)
        .overlay(shape.stroke(Sky.line, lineWidth: 1))
        .clipShape(shape)
        .animation(.spring(response: 0.4, dampingFraction: 0.86), value: controller.selected)
    }

    /// Shows content at its own height, or scrolls it once it would be taller than `maxHeight`.
    private func fitted<Content: View>(maxHeight: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
        let inner = content()
        return ViewThatFits(in: .vertical) {
            inner
            ScrollView(showsIndicators: false) { inner }
        }
        .frame(maxHeight: maxHeight)
    }

    /// Tap or drag the handle: up for the full list, down to fold the sheet away again.
    private var grabber: some View {
        Capsule()
            .fill(Color.white.opacity(0.28))
            .frame(width: 38, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 9)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
            .onTapGesture { toggleSheet(up: controller.selected == nil && !listExpanded) }
            .gesture(DragGesture(minimumDistance: 12).onEnded { g in
                if abs(g.translation.height) > 24 { toggleSheet(up: g.translation.height < 0) }
            })
            .accessibilityElement()
            .accessibilityLabel(listExpanded ? "Hide the list of planets" : "Show the list of planets")
            .accessibilityAddTraits(.isButton)
    }

    private func toggleSheet(up: Bool) {
        if up {
            listExpanded = true
        } else if controller.selected != nil {
            controller.fly(to: nil)
        } else {
            listExpanded = false
        }
    }

    private var dateHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 5) {
                Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Sky.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Sky.pill(relativeLabel, Int(offset.rounded()) == 0 ? Sky.green : Sky.amber)
            }
            Spacer(minLength: 8)
            if Int(offset.rounded()) != 0 {
                Button {
                    playing = false
                    withAnimation(.easeInOut(duration: 0.6)) { offset = 0 }
                    animateBackToToday()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Sky.text)
                        .frame(width: 40, height: 40)
                        .background(Sky.tile, in: Circle())
                }
                .accessibilityLabel("Back to today")
                .transition(.scale.combined(with: .opacity))
            }
            Button { speed = speed.next } label: {
                Text(speed.label)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(Sky.text)
                    .padding(.horizontal, 12).frame(height: 40)
                    .background(Sky.tile, in: Capsule())
                    .contentTransition(.numericText())
            }
            .accessibilityLabel("Playback speed \(speed.label)")
            .accessibilityHint("Changes how fast time moves")
            Button { playing.toggle() } label: {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 40, height: 40)
                    .background(Color.white, in: Circle())
            }
            .accessibilityLabel(playing ? "Pause time" : "Play time forward")
        }
    }

    /// Slides time back to today smoothly instead of jumping.
    private func animateBackToToday() {
        let start = offset
        Task {
            let steps = 30
            for i in 1...steps {
                let t = Double(i) / Double(steps)
                let eased = 1 - pow(1 - t, 3)
                offset = start * (1 - eased)
                try? await Task.sleep(for: .milliseconds(16))
            }
            offset = 0
        }
    }

    // MARK: Bodies

    private func position(_ p: Ephemeris.Placement) -> String { "\(p.sign.code) \(p.degreeInSign)°" }

    @ViewBuilder private func status(_ p: Ephemeris.Placement) -> some View {
        if p.retrograde { Sky.pill("Retrograde", Sky.orange) } else { Sky.pill("Direct", Sky.green) }
    }

    /// The folded sheet: one compact card per body, side by side.
    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(placements) { p in
                    Button { controller.fly(to: p.body) } label: {
                        HStack(spacing: 9) {
                            Circle().fill(Color(hex: p.body.colorHex)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.body.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(Sky.text)
                                Text(position(p))
                                    .font(.system(size: 12, weight: .medium))
                                    .monospacedDigit()
                                    .foregroundStyle(p.retrograde ? Sky.orange : Sky.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 52)
                        .background(Sky.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(p.body.name) in \(p.sign.name)\(p.retrograde ? ", retrograde" : "")")
                }
            }
        }
        .padding(.bottom, 6)
    }

    /// The sheet pulled up: every body as a row, with where it is and whether it's retrograde.
    private var bodyList: some View {
        VStack(spacing: 0) {
            ForEach(Array(placements.enumerated()), id: \.element.id) { i, p in
                if i > 0 { Rectangle().fill(Sky.line).frame(height: 1) }
                Button { controller.fly(to: p.body) } label: {
                    HStack(spacing: 12) {
                        Text(p.body.glyph)
                            .font(.system(size: 20))
                            .foregroundStyle(Color(hex: p.body.colorHex))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.body.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Sky.text)
                            Text(p.sign.name).font(.system(size: 13)).foregroundStyle(Sky.secondary)
                        }
                        Spacer(minLength: 8)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(position(p))
                                .font(.system(size: 17, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Sky.text)
                            status(p)
                        }
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Sky.faint)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(p.body.name) in \(p.sign.name)\(p.retrograde ? ", retrograde" : "")")
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: Detail

    @ViewBuilder private func detail(for body: Ephemeris.Body) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            hero(body)
            if body == .earth {
                Text("This is home. Every sign you see is measured from here: the gold line runs from Earth through a planet to the sign behind it.")
                    .font(.system(size: 15)).foregroundStyle(Sky.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let p = placements.first(where: { $0.body == body }) {
                route(p)
                tiles(p)
                Text(explanation(p))
                    .font(.system(size: 15)).foregroundStyle(Sky.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                askButton(p)
            }
        }
        .padding(.bottom, 8)
    }

    /// The close-up, with the name over it and a button to go back to the whole system.
    private func hero(_ body: Ephemeris.Body) -> some View {
        ZStack(alignment: .top) {
            PlanetHero(planet: body)
                .frame(height: 170)
                .frame(maxWidth: .infinity)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(body.name).font(.system(size: 30, weight: .heavy)).foregroundStyle(Sky.text)
                    if let p = placements.first(where: { $0.body == body }) { status(p) } else { Sky.pill("Home", Sky.green) }
                }
                Spacer()
                Button { controller.fly(to: nil) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Sky.secondary)
                        .frame(width: 32, height: 32)
                        .background(Sky.tile, in: Circle())
                }
                .accessibilityLabel("Back to the solar system")
            }
        }
    }

    /// Where the body is and where it goes next, laid out like a journey between two stops.
    private func route(_ p: Ephemeris.Placement) -> some View {
        let stay = controller.stay(p.body, days: days)
        let next = ZodiacSign.all[stay.next]
        let degrees = p.longitude.truncatingRemainder(dividingBy: 30)
        // Moving backwards, it heads for the start of the sign.
        let backwards = stay.next == (stay.sign + 11) % 12
        let progress = backwards ? 1 - degrees / 30 : degrees / 30
        return VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Sky.label("Now in")
                    Text(p.sign.code).font(.system(size: 40, weight: .heavy)).foregroundStyle(Sky.text)
                    Text(p.sign.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Sky.text)
                    Text(stay.entered.map { "since \(shortDate($0))" } ?? "for years")
                        .font(.system(size: 13)).monospacedDigit().foregroundStyle(Sky.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Sky.label("Next")
                    Text(next.code).font(.system(size: 40, weight: .heavy)).foregroundStyle(Sky.secondary)
                    Text(next.name).font(.system(size: 14, weight: .medium)).foregroundStyle(Sky.text)
                    Text(stay.leaves.map { "from \(shortDate($0))" } ?? "years away")
                        .font(.system(size: 13)).monospacedDigit().foregroundStyle(Sky.secondary)
                }
            }
            GeometryReader { geo in
                let x = max(7, min(geo.size.width - 7, geo.size.width * progress))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14)).frame(height: 4)
                    Capsule().fill(Color.white).frame(width: x, height: 4)
                    Circle()
                        .fill(Color(hex: p.body.colorHex))
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .frame(width: 14, height: 14)
                        .offset(x: x - 7)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 14)
            .accessibilityElement()
            .accessibilityLabel("\(Int((progress * 100).rounded())) percent of the way to \(next.name)")
        }
    }

    private func tiles(_ p: Ephemeris.Placement) -> some View {
        let motion = Ephemeris.dailyMotion(p.body, days: days)
        let distance = Ephemeris.distanceFromEarth(p.body, days: days)
        return HStack(spacing: 8) {
            tile("Speed", String(format: "%.2f°", abs(motion)), "per day")
            tile("From Earth",
                 p.body == .moon ? "384k" : String(format: "%.2f", distance ?? 0),
                 p.body == .moon ? "km" : "AU")
            let retro = retrograde(p.body)
            tile(retro.title, retro.value, retro.note)
        }
    }

    private func tile(_ label: String, _ value: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Sky.label(label)
            Text(value)
                .font(.system(size: 19, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Sky.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(note).font(.system(size: 12)).monospacedDigit().foregroundStyle(Sky.secondary).lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Sky.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func retrograde(_ body: Ephemeris.Body) -> (title: String, value: String, note: String) {
        guard let period = Ephemeris.retrogradePeriod(body, near: days) else { return ("Retrograde", "Never", "always direct") }
        if days >= period.start { return ("Retrograde", "Now", "until \(shortDate(period.end))") }
        return ("Retrograde", shortDate(period.start), "until \(shortDate(period.end))")
    }

    private func askButton(_ p: Ephemeris.Placement) -> some View {
        let psychic = app.matchedPsychic
        return Button {
            let when = Int(offset.rounded()) == 0 ? "right now" : "on \(date.formatted(date: .long, time: .omitted))"
            let question = "\(p.body.name) is in \(p.sign.name)\(p.retrograde ? " and retrograde" : "") \(when). What does that mean for me?"
            let sky = placements.map { "\($0.body.name) \($0.sign.name) \($0.degreeInSign)°\($0.retrograde ? " retrograde" : "")" }
                .joined(separator: ", ")
            let note = "[The user is looking at the sky in the app's cosmic view, for \(date.formatted(date: .long, time: .omitted)). Positions: \(sky). Read it for them in your own voice; keep it fun.]"
            onAsk(question, note)
            dismiss()
        } label: {
            HStack(spacing: 10) {
                AvatarView(psychic: psychic, size: 28)
                Text("Ask \(psychic.short) what it means")
            }
        }
        .buttonStyle(SkyButtonStyle())
    }

    /// The sign the selected body is in, so crossing into a new sign can be felt.
    private var selectedSign: Int {
        guard let s = controller.selected, let p = placements.first(where: { $0.body == s }) else { return -1 }
        return Int(p.longitude / 30)
    }

    private func explanation(_ p: Ephemeris.Placement) -> String {
        var s = "\(p.body.name) rules \(p.body.rules). In \(p.sign.name) it's \(p.sign.flavour)."
        if p.retrograde {
            s += " Retrograde: seen from Earth it looks like it's moving backwards, so its themes come back for a second look."
        }
        return s
    }
}

/// A ruler you drag sideways to move through time. Each tick is a day; long ticks mark the 1st of a month.
private struct TimeRuler: View {
    @Binding var offset: Double
    /// Haptic tick per day; off while time plays fast.
    var ticks = true
    var onScrubStart: () -> Void
    @State private var dragStart: Double?
    private let pointsPerDay: CGFloat = 9

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                let mid = size.width / 2
                let visibleDays = Int(size.width / pointsPerDay / 2) + 2
                let cal = Calendar.current
                let base = Date().addingTimeInterval(offset.rounded(.down) * 86_400)
                let frac = CGFloat(offset - offset.rounded(.down))
                for i in -visibleDays...visibleDays {
                    let x = mid + (CGFloat(i) - frac) * pointsPerDay
                    let day = base.addingTimeInterval(Double(i) * 86_400)
                    let isMonth = cal.component(.day, from: day) == 1
                    let h: CGFloat = isMonth ? 18 : 8
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height - h))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(path, with: .color(isMonth ? NightTheme.textSoft : NightTheme.borderStrong), lineWidth: isMonth ? 1.5 : 1)
                    if isMonth {
                        let text = Text(day.formatted(.dateTime.month(.abbreviated)))
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(NightTheme.muted)
                        ctx.draw(text, at: CGPoint(x: x, y: 6))
                    }
                }
                var needle = Path()
                needle.move(to: CGPoint(x: mid, y: 12))
                needle.addLine(to: CGPoint(x: mid, y: size.height))
                ctx.stroke(needle, with: .color(NightTheme.gold), lineWidth: 2.5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { g in
                        if dragStart == nil { dragStart = offset; onScrubStart() }
                        offset = (dragStart ?? 0) - Double(g.translation.width / pointsPerDay)
                    }
                    .onEnded { g in
                        // Coast a little, like a flick.
                        let v = Double(g.predictedEndTranslation.width - g.translation.width) / Double(pointsPerDay)
                        let start = offset
                        dragStart = nil
                        Task {
                            for i in 1...20 {
                                let t = Double(i) / 20
                                offset = start - v * (1 - pow(1 - t, 3))
                                try? await Task.sleep(for: .milliseconds(16))
                            }
                        }
                    }
            )
            .sensoryFeedback(.selection, trigger: ticks ? Int(offset.rounded()) : 0)
        }
        .frame(height: 34)
        .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
        .accessibilityElement()
        .accessibilityLabel("Date")
        .accessibilityAdjustableAction { direction in
            offset += direction == .increment ? 1 : -1
        }
    }
}
