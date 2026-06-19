//
//  GlobeView.swift
//  kodAI_chatbot_dev
//
//  "Decision Globe" — a generation trace wrapped onto a transparent glass
//  sphere. Each analyzed token is a bead on a pole-to-pole spiral; the chosen
//  path is the ribbon threading them; tokens that differ from the raw model
//  argmax leave a small gold satellite. The camera is fixed —
//  we rotate the globe node itself: drag to turn it by hand, scrub generation
//  time to spin the active token to front-center (a fixed playhead), and only
//  the focused token branches into "vessels" — one faint filament per weighed
//  raw alternative the model did not emit, the raw argmax glowing gold when it
//  differs from the emitted token. Reuses TokenSnapshot/TokenAlternative and
//  TokenVisuals so raw probability reads consistently across interpretation views.
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
/// the focused token's vessels. Taps select a bead via hit-testing.
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
        private var vesselContainer: SCNNode?
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
            scene.rootNode.addChildNode(GlobeChrome.silhouetteRing(radius: 0.99))
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
            vesselContainer = nil
            renderedSteps = tokens.map(\.step)

            let positions = GlobeLayout.positions(count: tokens.count)

            // Clear fresnel glass shell — no lat/long guides; the silhouette ring
            // (added once at the scene root) defines the orb instead.
            globeNode.addChildNode(GlobeChrome.glassShell(radius: 0.97))

            // Tracer: a strand threading the emitted path in token order, tinted by
            // each token's raw probability so the trajectory itself carries the heat.
            if positions.count > 1 {
                globeNode.addChildNode(makeTracer(positions))
            }

            // Beads, one per token, colored by raw probability; deviations from
            // the raw argmax get a gold diamond.
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

                if token.differsFromRawArgmax {
                    let moon = SCNPyramid(width: 0.026, height: 0.036, length: 0.026)
                    let moonMat = SCNMaterial()
                    moonMat.diffuse.contents = UIColor(TokenVisuals.divergenceColor)
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

        /// The emitted-path tracer, tinted per-vertex by raw token probability
        /// (gold where the emitted token differs from the raw argmax) so the strand
        /// as the trajectory's heat. Positions are in token order.
        private func makeTracer(_ positions: [SCNVector3]) -> SCNNode {
            let source = SCNGeometrySource(vertices: positions)

            // Per-vertex RGBA color, interpolated along each segment.
            var components: [Float] = []
            components.reserveCapacity(positions.count * 4)
            for (i, _) in positions.enumerated() {
                let color: UIColor = i < tokens.count
                    ? UIColor(TokenVisuals.confidenceColor(tokens[i].selectedProbability))
                    : UIColor(white: 1, alpha: 1)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.getRed(&r, green: &g, blue: &b, alpha: &a)
                components.append(contentsOf: [Float(r), Float(g), Float(b), 0.85])
            }
            let colorData = components.withUnsafeBytes { Data($0) }
            let colorSource = SCNGeometrySource(
                data: colorData,
                semantic: .color,
                vectorCount: positions.count,
                usesFloatComponents: true,
                componentsPerVector: 4,
                bytesPerComponent: MemoryLayout<Float>.size,
                dataOffset: 0,
                dataStride: MemoryLayout<Float>.size * 4
            )

            var indices: [Int32] = []
            indices.reserveCapacity((positions.count - 1) * 2)
            for i in 0..<(positions.count - 1) {
                indices.append(Int32(i)); indices.append(Int32(i + 1))
            }
            let element = SCNGeometryElement(indices: indices, primitiveType: .line)
            let geometry = SCNGeometry(sources: [source, colorSource], elements: [element])
            let mat = SCNMaterial()
            mat.lightingModel = .constant
            mat.writesToDepthBuffer = false
            geometry.firstMaterial = mat
            return SCNNode(geometry: geometry)
        }

        // MARK: Focus + vessels

        /// Brings `step`'s bead to front-center and blooms its top-k vessels.
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
            rebuildVessels(for: step, at: pos)
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

        /// Blooms the focused token's "vessels": a filament from the chosen bead
        /// out to each top raw alternative the model did *not* emit. Those branches
        /// are greyed and translucent; the raw argmax glows gold when it differs
        /// from the emitted token.
        /// Only the focused token blooms — every other bead stays a clean dot, so
        /// the globe shows just what you're looking at.
        private func rebuildVessels(for step: Int, at pos: SCNVector3) {
            vesselContainer?.removeFromParentNode()
            selectedBead?.scale = SCNVector3(1, 1, 1)

            guard let token = tokens.first(where: { $0.step == step }) else { return }

            // Emphasize the chosen bead — the sampled token itself needs no
            // branch; the strand threading the beads already carries it forward.
            if let bead = globeNode.childNode(withName: "bead:\(step)", recursively: false) {
                bead.scale = SCNVector3(1.8, 1.8, 1.8)
                selectedBead = bead
            }

            let container = SCNNode()

            // Branch only the considerations (everything that wasn't sampled).
            let considered = Array(token.alternatives.filter { !$0.isSelected }.prefix(5))
            if !considered.isEmpty {
                // Tangent basis at the token so vessels fan across the local surface.
                let n = v_norm(pos)
                var u = v_cross(n, SCNVector3(0, 1, 0))
                if v_len(u) < 1e-3 { u = v_cross(n, SCNVector3(1, 0, 0)) }
                u = v_norm(u)
                let w = v_norm(v_cross(n, u))

                let origin = v_add(pos, v_scale(n, 0.02))
                let rawArgmaxID = token.rawArgmaxAlternative?.tokenID

                for (j, alt) in considered.enumerated() {
                    let angle = Float(j) / Float(considered.count) * 2 * .pi
                    let dir = v_add(v_scale(u, cos(angle)), v_scale(w, sin(angle)))
                    // More-probable considerations reach a little further out.
                    let reach = Float(0.12 + 0.10 * alt.probability)
                    let tip = v_add(v_add(pos, v_scale(n, 0.05)), v_scale(dir, reach))

                    // The raw argmax glows gold when it differs from the emitted
                    // token; other top raw alternatives stay faint grey.
                    let isRawArgmax = token.differsFromRawArgmax && alt.tokenID == rawArgmaxID
                    let color = isRawArgmax
                        ? UIColor(TokenVisuals.divergenceColor)
                        : UIColor(white: 0.78, alpha: 1)
                    let opacity: CGFloat = isRawArgmax ? 0.72 : 0.3
                    let thickness: CGFloat = isRawArgmax ? 0.0034 : 0.0022

                    container.addChildNode(
                        makeVessel(from: origin, to: tip, radius: thickness, color: color, opacity: opacity)
                    )

                    // A small node at the vessel tip, sized by the option's odds.
                    let nodeGeo = SCNSphere(radius: CGFloat(0.006 + 0.018 * alt.probability))
                    let nodeMat = SCNMaterial()
                    nodeMat.diffuse.contents = color.withAlphaComponent(opacity)
                    nodeMat.lightingModel = .constant
                    nodeMat.writesToDepthBuffer = false
                    nodeGeo.firstMaterial = nodeMat
                    let tipNode = SCNNode(geometry: nodeGeo)
                    tipNode.position = tip
                    container.addChildNode(tipNode)

                    // Camera-facing label at the tip (≤5, focused token only).
                    container.addChildNode(
                        makeTipLabel(vesselLabel(alt), at: v_add(tip, v_scale(n, 0.03)), bright: isRawArgmax)
                    )
                }
            }

            globeNode.addChildNode(container)
            vesselContainer = container
        }

        /// A thin cylinder ("vessel") spanning two points around the globe. Built
        /// along +Y by SceneKit, then rotated so +Y aligns with the span.
        private func makeVessel(from a: SCNVector3, to b: SCNVector3, radius: CGFloat, color: UIColor, opacity: CGFloat) -> SCNNode {
            let diff = SCNVector3(b.x - a.x, b.y - a.y, b.z - a.z)
            let length = v_len(diff)
            let cylinder = SCNCylinder(radius: radius, height: CGFloat(max(length, 1e-4)))
            let mat = SCNMaterial()
            mat.diffuse.contents = color.withAlphaComponent(opacity)
            mat.lightingModel = .constant
            mat.writesToDepthBuffer = false
            cylinder.firstMaterial = mat
            let node = SCNNode(geometry: cylinder)
            node.position = v_scale(v_add(a, b), 0.5)

            let d = v_norm(diff)
            let up = SCNVector3(0, 1, 0)
            let axis = v_cross(up, d)
            let axisLen = v_len(axis)
            if axisLen > 1e-5 {
                let dot = max(-1, min(1, up.x * d.x + up.y * d.y + up.z * d.z))
                node.rotation = SCNVector4(axis.x / axisLen, axis.y / axisLen, axis.z / axisLen, acos(dot))
            } else if d.y < 0 {
                node.rotation = SCNVector4(1, 0, 0, Float.pi)
            }
            return node
        }

        /// Small camera-facing text at a vessel tip. Lives in the scene so it
        /// tracks the 3D point; only ever drawn for the one focused token.
        private func makeTipLabel(_ text: String, at pos: SCNVector3, bright: Bool) -> SCNNode {
            let geo = SCNText(string: text, extrusionDepth: 0)
            geo.font = .systemFont(ofSize: 8, weight: .semibold)
            geo.flatness = 0.4
            let mat = SCNMaterial()
            mat.diffuse.contents = bright
                ? UIColor(TokenVisuals.divergenceColor)
                : UIColor(white: 1, alpha: 0.85)
            mat.lightingModel = .constant
            mat.writesToDepthBuffer = false
            geo.firstMaterial = mat
            let node = SCNNode(geometry: geo)

            // SCNText is large and corner-anchored; center its pivot, then shrink.
            let (minB, maxB) = geo.boundingBox
            node.pivot = SCNMatrix4MakeTranslation((minB.x + maxB.x) / 2, (minB.y + maxB.y) / 2, 0)
            node.scale = SCNVector3(0.006, 0.006, 0.006)
            node.position = pos
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .all
            node.constraints = [billboard]
            node.renderingOrder = 20
            return node
        }

        /// Compact, legible label for a considered token piece.
        private func vesselLabel(_ alt: TokenAlternative) -> String {
            let trimmed = alt.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = trimmed.isEmpty ? (alt.text == "\n" ? "⏎" : "␣") : trimmed
            return base.count > 10 ? String(base.prefix(10)) + "…" : base
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
                        focusedGlobeLabel
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
                    Text("\(tokens.count) tokens · drag to rotate · scrub to replay")
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
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    rawProbabilityLegend
                    entropyLegend
                }
                VStack(alignment: .leading, spacing: 4) {
                    rawProbabilityLegend
                    entropyLegend
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    rawArgmaxLegend
                    alternativesLegend
                }
                VStack(alignment: .leading, spacing: 4) {
                    rawArgmaxLegend
                    alternativesLegend
                }
            }

            Text("Sampling telemetry only: spiral position is generation order, not meaning or hidden reasoning.")
                .foregroundStyle(.white.opacity(0.58))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.48))
        .padding(.horizontal, 18)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rawProbabilityLegend: some View {
        Label {
            Text("color = raw token probability")
        } icon: {
            LinearGradient(
                colors: [
                    TokenVisuals.confidenceColor(0),
                    TokenVisuals.confidenceColor(0.5),
                    TokenVisuals.confidenceColor(1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 18, height: 7)
            .clipShape(Capsule())
        }
    }

    private var entropyLegend: some View {
        Label {
            Text("size = raw entropy")
        } icon: {
            HStack(spacing: 2) {
                Circle().fill(.white.opacity(0.55)).frame(width: 4, height: 4)
                Circle().fill(.white.opacity(0.55)).frame(width: 8, height: 8)
            }
        }
    }

    private var rawArgmaxLegend: some View {
        Label {
            Text("gold diamond = differs from raw argmax")
        } icon: {
            Image(systemName: "diamond.fill")
                .foregroundStyle(TokenVisuals.divergenceColor)
                .font(.system(size: 7))
        }
    }

    private var alternativesLegend: some View {
        Label {
            Text("branches = top raw alternatives")
        } icon: {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 8))
        }
    }

    private var playhead: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.white.opacity(0.5),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
                .frame(width: 52, height: 52)
            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 4, height: 4)
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 70, height: 0.5)
            Rectangle()
                .fill(Color.white.opacity(0.3))
                .frame(width: 0.5, height: 70)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The focused token's identity, pinned just above the playhead so the
    /// centered bead is never an anonymous dot. Lives in SwiftUI (not the scene)
    /// to stay crisp and respect Dynamic Type.
    @ViewBuilder
    private var focusedGlobeLabel: some View {
        if let token = activeToken {
            Text(readableTokenText(token.text))
                .font(.callout.monospaced().bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(.black.opacity(0.4), in: Capsule())
                .offset(y: -46)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
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
                        Text("\(percent(token.selectedProbability))% raw p")
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

                    Text("Raw probability is measured before repetition penalties, truncation, temperature, and sampling. It is not answer correctness.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))

                    if token.differsFromRawArgmax, let rawArgmax = token.rawArgmaxAlternative {
                        Label(
                            "Raw argmax: \(readableTokenText(rawArgmax.text)) (\(percent(rawArgmax.probability))%)",
                            systemImage: "diamond.fill"
                        )
                        .font(.caption2)
                        .foregroundStyle(TokenVisuals.divergenceColor.opacity(0.95))
                    }

                    HStack(spacing: 18) {
                        metric("Entropy", String(format: "%.2f nats", token.entropy))
                        metric("Raw margin", "\(percent(token.margin)) pp")
                        metric("Surprise", String(format: "%.2f nats", -log(max(token.selectedProbability, 1e-6))))
                    }

                    Text("Nats measure raw-distribution spread: ~0 is concentrated; ~4 has an effective support near 55 equally weighted tokens. Surprise is -log(raw p) for the emitted token.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.45))

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
            piece.foregroundColor = isSelected ? .white : .white.opacity(0.62)
            if isSelected { piece.inlinePresentationIntent = .stronglyEmphasized }
            result += piece
        }
        return result
    }

    private func takeaway(for token: TokenSnapshot) -> String {
        let selected = readableTokenText(token.text)
        if token.differsFromRawArgmax, let rawArgmax = token.rawArgmaxAlternative {
            return "“\(selected)” was emitted at \(percent(token.selectedProbability))% raw probability; the raw argmax was “\(readableTokenText(rawArgmax.text))” at \(percent(rawArgmax.probability))%. Sampler controls determine the final choice."
        }
        if token.selectedProbability >= 0.75 {
            return "The raw model distribution strongly favored “\(selected)” at \(percent(token.selectedProbability))%."
        }
        if token.margin < 0.08 {
            return "“\(selected)” was the raw argmax, but the two leading raw probabilities were close."
        }
        return "“\(selected)” was the raw argmax, with other raw alternatives still carrying probability."
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
