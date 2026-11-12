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
        for body in Ephemeris.Body.allCases where body != .moon {
            labels[body.rawValue] = makeLabel(glyph: nil, name: body.name, color: .white, size: body == .sun ? 13 : 12)
        }
        for (i, sign) in ZodiacSign.all.enumerated() {
            labels["sign\(i)"] = makeLabel(glyph: sign.glyph, name: sign.name, color: UIColor(Theme.gold), size: 12, weight: .bold)
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

    /// Starts far out in space and swoops in.
    func playIntro() {
        let cam = cosmos.cameraNode
        cam.position = SCNVector3(-30, 70, 110)
        cam.look(at: SCNVector3Zero)
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 2.6
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
        cam.position = Self.overview
        cam.look(at: Self.overviewAim, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        SCNTransaction.commit()
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
        cosmos.pointOfView = view.pointOfView
        if let eye = view.pointOfView?.presentation.worldPosition { cosmos.sizeSelectionRing(cameraAt: eye, selected: selected) }
        let h = view.bounds.height
        var taken: [CGRect] = []
        func place(_ key: String, at p: SCNVector3, offset: CGFloat, alpha: CGFloat, size: CGSize, force: Bool = false) {
            guard let label = labels[key] else { return }
            let s = view.projectPoint(p)
            guard s.z > 0, s.z < 1, s.x > -60, s.x < Float(view.bounds.width) + 60 else { label.isHidden = true; return }
            let pos = CGPoint(x: CGFloat(s.x), y: h - CGFloat(s.y) + offset)
            let rect = CGRect(x: pos.x - size.width / 2, y: pos.y - size.height / 2, width: size.width, height: size.height)
            if !force, taken.contains(where: { $0.intersects(rect) }) { label.isHidden = true; return }
            taken.append(rect)
            label.isHidden = false
            label.position = pos
            label.alpha = alpha
        }
        // Most important first: the selected body, the Sun, Earth, then the big planets.
        var order: [Ephemeris.Body] = [.sun, .earth, .jupiter, .saturn, .mars, .venus, .mercury, .uranus, .neptune]
        if let selected, let i = order.firstIndex(of: selected) { order.remove(at: i); order.insert(selected, at: 0) }
        for body in order {
            guard let node = cosmos.bodyNodes[body] else { continue }
            let dimmed = selected != nil && selected != body && body != .earth
            let width = CGFloat(body.name.count) * 7.5 + 6
            // How big the body looks on screen, so the label sits just under its edge at any zoom.
            let up = view.pointOfView?.presentation.worldUp ?? SCNVector3(0, 1, 0)
            let r = cosmos.radius(of: body)
            let c = node.presentation.position
            let edge = view.projectPoint(SCNVector3(c.x + up.x * r, c.y + up.y * r, c.z + up.z * r))
            let center = view.projectPoint(c)
            let screenRadius = CGFloat(min(hypot(edge.x - center.x, edge.y - center.y), 400))
            place(body.rawValue, at: c, offset: -(screenRadius + 11), alpha: dimmed ? 0.5 : 1,
                  size: CGSize(width: width, height: 16), force: body == selected)
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
    /// The detail card shows one line until tapped.
    @State private var detailExpanded = false
    /// Height of the bottom panel; the 3D view fits in the space above it so the Sun stays centred.
    @State private var panelHeight: CGFloat = 250
    /// Called with a question and context for Claude when the user asks their psychic about the sky.
    var onAsk: (String, String) -> Void = { _, _ in }

    private let now = Date()
    private var date: Date { now.addingTimeInterval(offset * 86_400) }
    private var placements: [Ephemeris.Placement] { Ephemeris.placements(on: date) }

    var body: some View {
        ZStack {
            CosmosSceneView(controller: controller)
                .padding(.bottom, max(panelHeight - 24, 0))
                .ignoresSafeArea(edges: .top)
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
                    .frame(height: 170)
                    .ignoresSafeArea(edges: .top)
                Spacer()
            }
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                if showHint { hint.transition(.opacity) }
                Spacer()
                panel
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

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            circleButton("xmark", label: "Close") { dismiss() }
            Spacer()
            VStack(spacing: 2) {
                Text("Cosmic view").font(Theme.display(19)).foregroundStyle(Theme.textBright)
                Text(controller.selected.map { "Following \($0.name)" } ?? "The solar system")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
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
            .foregroundStyle(Theme.textSoft)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.top, 10)
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textBright)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(label)
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                        .font(Theme.display(24, .medium))
                        .foregroundStyle(Theme.textBright)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .contentTransition(.numericText())
                    Text(relativeLabel).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.gold)
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
                            .foregroundStyle(Theme.textBright)
                            .frame(width: 36, height: 36)
                            .background(Theme.surfaceRaised, in: Circle())
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
                        .foregroundStyle(Theme.textBright)
                        .padding(.horizontal, 11).frame(height: 36)
                        .background(Theme.surfaceRaised, in: Capsule())
                        .contentTransition(.numericText())
                }
                .accessibilityLabel("Playback speed \(speed.label)")
                .accessibilityHint("Changes how fast time moves")
                Button { playing.toggle() } label: {
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Theme.onGold)
                        .frame(width: 40, height: 40)
                        .background(Theme.gold, in: Circle())
                }
                .accessibilityLabel(playing ? "Pause time" : "Play time forward")
            }

            TimeRuler(offset: $offset, ticks: !playing || speed == .day, onScrubStart: { playing = false })

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(placements) { p in
                            chip(p).id(p.body)
                        }
                    }
                }
                .onChange(of: controller.selected) { _, new in
                    detailExpanded = false
                    if let new { withAnimation { proxy.scrollTo(new, anchor: .center) } }
                }
            }

            if let selected = controller.selected { detail(for: selected) }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.bg.opacity(0.55)))
        )
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .background(GeometryReader { g in
            Color.clear
                .onAppear { panelHeight = g.size.height }
                .onChange(of: g.size.height) { _, h in panelHeight = h }
        })
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: controller.selected)
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

    private func chip(_ p: Ephemeris.Placement) -> some View {
        let isSelected = controller.selected == p.body
        return Button { controller.fly(to: isSelected ? nil : p.body) } label: {
            HStack(spacing: 8) {
                Text(p.body.glyph)
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: p.body.colorHex))
                VStack(alignment: .leading, spacing: 1) {
                    Text(p.body.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textBright)
                    Text("\(p.sign.glyph) \(p.sign.name) \(p.degreeInSign)°\(p.retrograde ? " ℞" : "")")
                        .font(.system(size: 12))
                        .foregroundStyle(p.retrograde ? Color(hex: 0xF0A27A) : Theme.muted)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 50)
            .background(isSelected ? Color(hex: 0x2A2350) : Theme.surface.opacity(0.8),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Theme.gold : Theme.border, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(p.body.name) in \(p.sign.name)\(p.retrograde ? ", retrograde" : "")")
    }

    @ViewBuilder private func detail(for body: Ephemeris.Body) -> some View {
        if body == .earth {
            Text("This is home. Every sign you see is measured from here: the gold line runs from Earth through a planet to the sign behind it.")
                .font(.system(size: 14)).foregroundStyle(Theme.textSoft)
                .fixedSize(horizontal: false, vertical: true)
        } else if let p = placements.first(where: { $0.body == body }) {
            let psychic = app.matchedPsychic
            VStack(alignment: .leading, spacing: 8) {
                Button { withAnimation(.easeInOut(duration: 0.25)) { detailExpanded.toggle() } } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(body.name) in \(p.sign.name)\(p.retrograde ? ", retrograde" : "")")
                                .font(Theme.display(20)).foregroundStyle(Theme.gold)
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.muted)
                                .rotationEffect(.degrees(detailExpanded ? 180 : 0))
                        }
                        Text(explanation(p))
                            .font(.system(size: 14)).foregroundStyle(Theme.textSoft)
                            .lineLimit(detailExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint(detailExpanded ? "Shows less" : "Shows more")
                if let retro = retrogradeLine(body) {
                    Label(retro, systemImage: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xF0A27A))
                }
                Button {
                    let when = Int(offset.rounded()) == 0 ? "right now" : "on \(date.formatted(date: .long, time: .omitted))"
                    let question = "\(body.name) is in \(p.sign.name)\(p.retrograde ? " and retrograde" : "") \(when). What does that mean for me?"
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
                .buttonStyle(GoldButtonStyle())
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func retrogradeLine(_ body: Ephemeris.Body) -> String? {
        let d = Ephemeris.daysSinceJ2000(date)
        guard let period = Ephemeris.retrogradePeriod(body, near: d) else { return nil }
        let f = Date.FormatStyle().month(.abbreviated).day()
        let start = Ephemeris.date(days: period.start), end = Ephemeris.date(days: period.end)
        let sameYear = Calendar.current.isDate(end, equalTo: date, toGranularity: .year)
        let endText = sameYear ? end.formatted(f) : end.formatted(f.year())
        if d >= period.start { return "Retrograde \(start.formatted(f)) – \(endText)" }
        return "Next retrograde \(start.formatted(f)) – \(endText)"
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
                    ctx.stroke(path, with: .color(isMonth ? Theme.textSoft : Theme.borderStrong), lineWidth: isMonth ? 1.5 : 1)
                    if isMonth {
                        let text = Text(day.formatted(.dateTime.month(.abbreviated)))
                            .font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.muted)
                        ctx.draw(text, at: CGPoint(x: x, y: 6))
                    }
                }
                var needle = Path()
                needle.move(to: CGPoint(x: mid, y: 12))
                needle.addLine(to: CGPoint(x: mid, y: size.height))
                ctx.stroke(needle, with: .color(Theme.gold), lineWidth: 2.5)
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
