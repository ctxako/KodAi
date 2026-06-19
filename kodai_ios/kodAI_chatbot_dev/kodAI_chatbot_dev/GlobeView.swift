//
//  GlobeView.swift
//  kodAI_chatbot_dev
//
//  "Decision Globe" — a generation trace wrapped onto a transparent glass
//  sphere. Each analyzed token is a bead on a pole-to-pole spiral; the chosen
//  path is the ribbon threading them; sampling forks (where the model didn't
//  follow its own top pick) leave a small red satellite. The camera is fixed —
//  we rotate the globe node itself: drag to turn it by hand, scrub generation
//  time to spin the active token to front-center (a fixed playhead), and only
//  the focused token blooms its top-k alternatives as orbiting shards. Reuses
//  TokenSnapshot/TokenAlternative and TokenVisuals so confidence reads exactly
//  as it does in the heatmap, inspector, and river.
//
//  This is a decision trace through probability space — not "thoughts."
//

import KodaiKernel
import SceneKit
import SwiftUI

// MARK: - Spiral layout

/// Resolves each analyzed token's position on the unit sphere. Tokens wind from
/// near the north pole (step 0) down to the south, the spiral tightening with
/// length so long responses stay on the surface instead of crowding one ring.
private enum GlobeLayout {
    static func positions(count: Int) -> [SCNVector3] {
        guard count > 0 else { return [] }
        // Scale smoothly with length so longer traces keep useful separation.
        let turns = min(18, max(2, sqrt(Double(count)) * 0.8))
        var result: [SCNVector3] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            let t = count > 1 ? Double(i) / Double(count - 1) : 0.5
            // Keep off the exact poles so beads never pile onto a single point.
            let polar = (0.12 + 0.76 * t) * .pi
            let y = cos(polar)
            let ring = sin(polar)
            let lon = t * turns * 2 * .pi
            let x = ring * cos(lon)
            let z = ring * sin(lon)
            result.append(SCNVector3(Float(x), Float(y), Float(z)))
        }
        return result
    }
}

// MARK: - Vector helpers

private func v_add(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
    SCNVector3(a.x + b.x, a.y + b.y, a.z + b.z)
}
private func v_scale(_ a: SCNVector3, _ s: Float) -> SCNVector3 {
    SCNVector3(a.x * s, a.y * s, a.z * s)
}
private func v_len(_ a: SCNVector3) -> Float {
    sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
}
private func v_norm(_ a: SCNVector3) -> SCNVector3 {
    let l = v_len(a)
    return l > 1e-5 ? v_scale(a, 1 / l) : a
}
private func v_cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
    SCNVector3(
        a.y * b.z - a.z * b.y,
        a.z * b.x - a.x * b.z,
        a.x * b.y - a.y * b.x
    )
}

// MARK: - Scene host

/// Wraps an `SCNView` and owns the globe node. The camera stays put; the
/// coordinator rotates the globe to bring `activeStep` to the front and rebuilds
/// the focused token's shards. Taps select a bead via hit-testing.
private struct GlobeSceneView: UIViewRepresentable {
    let tokens: [TokenSnapshot]
    @Binding var activeStep: Int?

    func makeCoordinator() -> Coordinator {
        Coordinator(tokens: tokens) { step in
            // Route a tapped bead back through SwiftUI state so the overlay card,
            // scrubber, and the spin-to-front all stay in sync.
            activeStep = step
        }
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.scene = context.coordinator.buildScene()
        view.pointOfView = context.coordinator.cameraNode

        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        let tap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleTap(_:))
        )
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(tap)
        context.coordinator.scnView = view

        // Land on the first token so the globe opens already oriented.
        if let first = tokens.first?.step {
            context.coordinator.focus(step: first, animated: false)
        }
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.update(tokens: tokens)
        if let step = activeStep, step != context.coordinator.currentStep {
            let animated = !UIAccessibility.isReduceMotionEnabled
            context.coordinator.focus(step: step, animated: animated)
        }
    }

    // MARK: Coordinator

    final class Coordinator: NSObject {
        var tokens: [TokenSnapshot]
        private let onSelect: (Int) -> Void

        weak var scnView: SCNView?
        let cameraNode = SCNNode()
        private let globeNode = SCNNode()
        private var beadPositions: [Int: SCNVector3] = [:]
        private var depthCuedNodes: [SCNNode] = []
        private var shardContainer: SCNNode?
        private var selectedBead: SCNNode?
        private var renderedSteps: [Int] = []

        // Orientation = spin (to face the active bead) + manual drag offset.
        private var spinYaw: Float = 0
        private var spinPitch: Float = 0
        private var dragYaw: Float = 0
        private var dragPitch: Float = 0
        private(set) var currentStep: Int?

        init(tokens: [TokenSnapshot], onSelect: @escaping (Int) -> Void) {
            self.tokens = tokens
            self.onSelect = onSelect
        }

        func buildScene() -> SCNScene {
            let scene = SCNScene()
            scene.background.contents = UIColor.clear

            cameraNode.camera = SCNCamera()
            cameraNode.camera?.fieldOfView = 48
            cameraNode.position = SCNVector3(0, 0, 3.6)
            scene.rootNode.addChildNode(cameraNode)

            buildGlobe()
            scene.rootNode.addChildNode(globeNode)
            return scene
        }

        func update(tokens newTokens: [TokenSnapshot]) {
            let steps = newTokens.map(\.step)
            tokens = newTokens
            guard steps != renderedSteps else { return }

            let stepToRestore = currentStep ?? steps.first
            buildGlobe()
            if let stepToRestore, beadPositions[stepToRestore] != nil {
                focus(step: stepToRestore, animated: false)
            }
        }

        private func buildGlobe() {
            globeNode.childNodes.forEach { $0.removeFromParentNode() }
            beadPositions.removeAll()
            depthCuedNodes.removeAll()
            selectedBead = nil
            shardContainer = nil
            renderedSteps = tokens.map(\.step)

            let positions = GlobeLayout.positions(count: tokens.count)

            // A nearly clear shell plus three restrained great-circle guides.
            // Constant materials avoid the blown-out highlights produced by a
            // two-sided physically based glass material.
            let shell = SCNSphere(radius: 0.97)
            shell.segmentCount = 48
            let glass = SCNMaterial()
            glass.diffuse.contents = UIColor(red: 0.18, green: 0.55, blue: 0.72, alpha: 1)
            glass.transparency = 0.025
            glass.transparencyMode = .singleLayer
            glass.blendMode = .screen
            glass.lightingModel = .constant
            glass.isDoubleSided = true
            glass.writesToDepthBuffer = false
            shell.firstMaterial = glass
            let shellNode = SCNNode(geometry: shell)
            shellNode.renderingOrder = -10
            globeNode.addChildNode(shellNode)

            globeNode.addChildNode(makeGuideRing(eulerAngles: SCNVector3(0, 0, 0)))
            globeNode.addChildNode(makeGuideRing(eulerAngles: SCNVector3(Float.pi / 2, 0, 0)))
            globeNode.addChildNode(makeGuideRing(eulerAngles: SCNVector3(0, 0, Float.pi / 2)))

            // Ribbon: a single neutral line strip threading the chosen path. Color
            // lives on the beads; the thread just shows the order of decisions.
            if positions.count > 1 {
                globeNode.addChildNode(makeRibbon(positions))
            }

            // Beads, one per token, colored by confidence; forks get a red moon.
            for (i, token) in tokens.enumerated() {
                let pos = positions[i]
                beadPositions[token.step] = pos

                let densityScale = max(0.58, min(1, sqrt(140 / CGFloat(max(tokens.count, 1)))))
                let radius = densityScale * (0.018 + 0.014 * CGFloat(min(1, token.entropy / TokenVisuals.entropyReferenceMax)))
                let bead = SCNSphere(radius: radius)
                let mat = SCNMaterial()
                mat.diffuse.contents = UIColor(TokenVisuals.confidenceColor(token.selectedProbability))
                mat.lightingModel = .constant
                bead.firstMaterial = mat
                let node = SCNNode(geometry: bead)
                node.position = pos
                node.name = "bead:\(token.step)"
                node.categoryBitMask = 2
                globeNode.addChildNode(node)
                depthCuedNodes.append(node)

                // Keep the visual bead delicate while meeting a forgiving touch
                // target through a larger invisible hit-test sphere.
                let hitTarget = SCNSphere(radius: max(0.055, radius * 2.2))
                let hitMaterial = SCNMaterial()
                hitMaterial.colorBufferWriteMask = []
                hitMaterial.writesToDepthBuffer = false
                hitTarget.firstMaterial = hitMaterial
                let hitNode = SCNNode(geometry: hitTarget)
                hitNode.position = pos
                hitNode.name = "bead:\(token.step)"
                hitNode.categoryBitMask = 2
                globeNode.addChildNode(hitNode)

                if token.divergedFromGreedy {
                    let moon = SCNPyramid(width: 0.026, height: 0.036, length: 0.026)
                    let moonMat = SCNMaterial()
                    moonMat.diffuse.contents = UIColor.systemRed
                    moonMat.lightingModel = .constant
                    moon.firstMaterial = moonMat
                    let moonNode = SCNNode(geometry: moon)
                    moonNode.position = v_add(pos, v_scale(v_norm(pos), 0.045))
                    moonNode.name = "bead:\(token.step)" // tappable as the same token
                    moonNode.categoryBitMask = 2
                    moonNode.eulerAngles.z = .pi / 4
                    globeNode.addChildNode(moonNode)
                    depthCuedNodes.append(moonNode)
                }
            }

            updateDepthCues()
        }

        private func makeRibbon(_ positions: [SCNVector3]) -> SCNNode {
            let source = SCNGeometrySource(vertices: positions)
            var indices: [Int32] = []
            indices.reserveCapacity((positions.count - 1) * 2)
            for i in 0..<(positions.count - 1) {
                indices.append(Int32(i))
                indices.append(Int32(i + 1))
            }
            let element = SCNGeometryElement(
                indices: indices,
                primitiveType: .line
            )
            let geometry = SCNGeometry(sources: [source], elements: [element])
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor(white: 1, alpha: 0.18)
            mat.lightingModel = .constant
            geometry.firstMaterial = mat
            return SCNNode(geometry: geometry)
        }

        private func makeGuideRing(eulerAngles: SCNVector3) -> SCNNode {
            let ring = SCNTorus(ringRadius: 0.974, pipeRadius: 0.0015)
            ring.ringSegmentCount = 96
            ring.pipeSegmentCount = 4
            let material = SCNMaterial()
            material.diffuse.contents = UIColor(red: 0.30, green: 0.82, blue: 0.94, alpha: 1)
            material.transparency = 0.13
            material.lightingModel = .constant
            material.writesToDepthBuffer = false
            ring.firstMaterial = material
            let node = SCNNode(geometry: ring)
            node.eulerAngles = eulerAngles
            node.renderingOrder = -8
            return node
        }

        // MARK: Focus + shards

        /// Brings `step`'s bead to front-center and blooms its top-k shards.
        func focus(step: Int, animated: Bool) {
            currentStep = step
            guard let pos = beadPositions[step] else { return }

            // Rotation that maps this bead's local position onto +Z (the camera
            // axis): yaw to its meridian, then pitch to lift it to the equator.
            let ring = sqrt(pos.x * pos.x + pos.z * pos.z)
            spinYaw = -atan2(pos.x, pos.z)
            spinPitch = atan2(pos.y, ring)
            dragYaw = 0
            dragPitch = 0

            applyOrientation(animated: animated)
            rebuildShards(for: step, at: pos)
        }

        private func applyOrientation(animated: Bool) {
            let pitch = max(-1.45, min(1.45, spinPitch + dragPitch))
            let target = SCNVector3(pitch, spinYaw + dragYaw, 0)
            if animated {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.55
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                globeNode.eulerAngles = target
                SCNTransaction.completionBlock = { [weak self] in
                    self?.updateDepthCues()
                }
                SCNTransaction.commit()
            } else {
                globeNode.eulerAngles = target
                updateDepthCues()
            }
        }

        private func updateDepthCues() {
            for node in depthCuedNodes {
                let z = node.presentation.worldPosition.z
                node.opacity = z < -0.08 ? 0.24 : (z < 0.18 ? 0.58 : 1)
            }
        }

        /// Rebuilds the orbiting alternatives for the focused token only — every
        /// other bead stays a clean dot, so the globe doesn't drown in labels.
        private func rebuildShards(for step: Int, at pos: SCNVector3) {
            shardContainer?.removeFromParentNode()
            selectedBead?.scale = SCNVector3(1, 1, 1)

            guard let token = tokens.first(where: { $0.step == step }) else { return }

            // Emphasize the chosen bead.
            if let bead = globeNode.childNode(withName: "bead:\(step)", recursively: false) {
                bead.scale = SCNVector3(1.8, 1.8, 1.8)
                selectedBead = bead
            }

            let container = SCNNode()

            // Alternatives remain graphical here; readable labels live in the
            // inspector, where they can never collide with one another.
            let alts = Array(token.alternatives.prefix(5))
            if alts.count > 1 {
                let n = v_norm(pos)
                var u = v_cross(n, SCNVector3(0, 1, 0))
                if v_len(u) < 1e-3 { u = v_cross(n, SCNVector3(1, 0, 0)) }
                u = v_norm(u)
                let w = v_norm(v_cross(n, u))

                for (j, alt) in alts.enumerated() {
                    let angle = Float(j) / Float(alts.count) * 2 * .pi
                    let dir = v_add(v_scale(u, cos(angle)), v_scale(w, sin(angle)))
                    let base = v_add(pos, v_scale(n, 0.06))
                    let shardPos = v_add(base, v_scale(dir, 0.16))

                    let r = CGFloat(0.008 + 0.020 * alt.probability)
                    let shard = SCNSphere(radius: r)
                    let mat = SCNMaterial()
                    let color = UIColor(TokenVisuals.confidenceColor(alt.probability))
                    mat.diffuse.contents = color.withAlphaComponent(alt.isSelected ? 0.95 : 0.38)
                    mat.lightingModel = .constant
                    shard.firstMaterial = mat
                    let shardNode = SCNNode(geometry: shard)
                    shardNode.position = shardPos
                    container.addChildNode(shardNode)
                }
            }

            globeNode.addChildNode(container)
            shardContainer = container
        }

        // MARK: Gestures

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let t = gesture.translation(in: view)
            dragYaw += Float(t.x) * 0.005
            dragPitch += Float(t.y) * 0.005
            gesture.setTranslation(.zero, in: view)
            applyOrientation(animated: false)
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = scnView else { return }
            let point = gesture.location(in: view)
            let hits = view.hitTest(point, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .categoryBitMask: 2,
            ])
            for hit in hits {
                guard let name = hit.node.name, name.hasPrefix("bead:"),
                      let step = Int(name.dropFirst("bead:".count)) else { continue }
                onSelect(step)
                return
            }
        }
    }
}

// MARK: - Decision Globe screen

struct GlobeView: View {
    let messageText: String
    let history: [TokenSnapshot]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var activeStep: Int?
    @State private var isInspectorExpanded = false

    /// Only tokens carrying a distribution map to beads; end-of-stream flush
    /// chunks (no alternatives) are dropped so the globe reflects real decisions.
    private var tokens: [TokenSnapshot] { history.filter(\.isAnalyzed) }

    private var activeToken: TokenSnapshot? {
        tokens.first { $0.step == activeStep } ?? tokens.first
    }

    private var activeIndex: Int {
        tokens.firstIndex { $0.step == activeStep } ?? 0
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground()

            RadialGradient(
                colors: [ChatPalette.accentBlue.opacity(0.16), .clear],
                center: .center,
                startRadius: 20,
                endRadius: 330
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if tokens.isEmpty {
                    emptyState
                        .frame(maxHeight: .infinity)
                } else {
                    legend

                    ZStack {
                        GlobeSceneView(tokens: tokens, activeStep: $activeStep)
                            .accessibilityHidden(true)
                        playhead
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)

                    timeline
                    focusedCard
                }
            }
        }
        .statusBarHidden()
        .onAppear { if activeStep == nil { activeStep = tokens.first?.step } }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Token Globe")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                if !tokens.isEmpty {
                    Text("\(tokens.count) tokens · generated from top to bottom")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .accessibilityLabel("Close generation globe")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            Label {
                Text("color = likelihood")
            } icon: {
                Circle()
                    .fill(TokenVisuals.confidenceColor(0.75))
                    .frame(width: 7, height: 7)
            }

            Label {
                Text("diamond = alternate pick")
            } icon: {
                Image(systemName: "diamond.fill")
                    .foregroundStyle(.red)
                    .font(.system(size: 7))
            }

            Label("time runs down", systemImage: "arrow.down")
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.48))
        .padding(.horizontal, 18)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var playhead: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.cyan.opacity(0.42),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
                .frame(width: 52, height: 52)
            Circle()
                .fill(Color.cyan.opacity(0.72))
                .frame(width: 4, height: 4)
            Rectangle()
                .fill(Color.cyan.opacity(0.28))
                .frame(width: 70, height: 0.5)
            Rectangle()
                .fill(Color.cyan.opacity(0.28))
                .frame(width: 0.5, height: 70)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var timeline: some View {
        HStack(spacing: 10) {
            timelineButton(systemImage: "chevron.left", delta: -1, label: "Previous token")

            Slider(value: stepIndexBinding, in: 0...Double(max(tokens.count - 1, 1)), step: 1)
                .tint(.white.opacity(0.72))
                .accessibilityLabel("Generation position")
                .accessibilityValue("Decision \(activeIndex + 1) of \(tokens.count)")

            timelineButton(systemImage: "chevron.right", delta: 1, label: "Next token")

            Text("\(activeIndex + 1)/\(tokens.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .frame(minWidth: 48, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }

    private func timelineButton(systemImage: String, delta: Int, label: String) -> some View {
        Button {
            let next = min(max(0, activeIndex + delta), tokens.count - 1)
            activeStep = tokens[next].step
            Haptics.lightTap()
        } label: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.08), in: Circle())
        }
        .foregroundStyle(.white.opacity(0.8))
        .disabled(activeIndex + delta < 0 || activeIndex + delta >= tokens.count)
        .accessibilityLabel(label)
    }

    private var stepIndexBinding: Binding<Double> {
        Binding(
            get: {
                Double(tokens.firstIndex { $0.step == activeStep } ?? 0)
            },
            set: { newValue in
                let idx = min(max(0, Int(newValue.rounded())), tokens.count - 1)
                activeStep = tokens[idx].step
            }
        )
    }

    @ViewBuilder
    private var focusedCard: some View {
        if let token = activeToken {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                        isInspectorExpanded.toggle()
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(readableTokenText(token.text))
                            .font(.title3.monospaced().bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Text("\(percent(token.selectedProbability))% likely")
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(TokenVisuals.confidenceColor(token.selectedProbability))

                        Image(systemName: "chevron.up")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.45))
                            .rotationEffect(.degrees(isInspectorExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text("Token \(activeIndex + 1) of \(tokens.count) · tap for details")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.43))

                Text(contextText(for: token))
                    .font(.caption.monospaced())
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(takeaway(for: token))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))

                if isInspectorExpanded {
                    Divider().overlay(.white.opacity(0.12))

                    Text("Probability is not correctness. It only shows how expected this next token was before sampling controls.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))

                    if token.divergedFromGreedy, let greedy = token.greedyAlternative {
                        Label(
                            "Raw top option: \(readableTokenText(greedy.text)) (\(percent(greedy.probability))%)",
                            systemImage: "diamond.fill"
                        )
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.82))
                    }

                    HStack(spacing: 18) {
                        metric("Entropy", String(format: "%.2f nats", token.entropy))
                        metric("Top margin", "\(percent(token.margin)) pp")
                        metric("Surprise", String(format: "%.2f nats", -log(max(token.selectedProbability, 1e-6))))
                    }

                    if token.alternatives.count > 1 {
                        Divider().overlay(.white.opacity(0.12))
                        Text("Top raw candidates")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.52))
                        TokenAlternativesList(alternatives: token.alternatives)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassPanel(
                tint: reduceTransparency ? ChatPalette.elevatedSurface : ChatPalette.elevatedSurface.opacity(0.72),
                cornerRadius: 22
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: token.step)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func contextText(for token: TokenSnapshot) -> AttributedString {
        guard let index = tokens.firstIndex(where: { $0.step == token.step }) else {
            return AttributedString(readableTokenText(token.text))
        }

        let start = max(0, index - 2)
        let end = min(tokens.count - 1, index + 2)
        var result = AttributedString()
        for position in start...end {
            let raw = tokens[position].text.replacingOccurrences(of: "\n", with: " ↵ ")
            let isSelected = position == index
            let text: String
            if isSelected {
                let leadingSpace = raw.first?.isWhitespace == true ? " " : ""
                text = leadingSpace + "[\(readableTokenText(raw))]"
            } else {
                text = raw
            }

            var piece = AttributedString(text)
            piece.foregroundColor = isSelected ? .cyan : .white.opacity(0.62)
            result += piece
        }
        return result
    }

    private func takeaway(for token: TokenSnapshot) -> String {
        let selected = readableTokenText(token.text)
        if token.divergedFromGreedy, let greedy = token.greedyAlternative {
            return "Sampling chose “\(selected)” (\(percent(token.selectedProbability))%) instead of the model’s top option “\(readableTokenText(greedy.text))” (\(percent(greedy.probability))%)."
        }
        if token.selectedProbability >= 0.75 {
            return "“\(selected)” was the model’s clear top option at \(percent(token.selectedProbability))%."
        }
        if token.margin < 0.08 {
            return "“\(selected)” won a close call; several next tokens had similar likelihood."
        }
        return "“\(selected)” was the top option, but meaningful alternatives remained."
    }

    private func readableTokenText(_ text: String) -> String {
        if text == "\n" { return "newline" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "space" : trimmed
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("No token trace for this response.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func percent(_ value: Float) -> Int {
        Int((value * 100).rounded())
    }
}
