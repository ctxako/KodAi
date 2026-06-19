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
        // More tokens → more turns, capped so the ribbon never becomes a blur.
        let turns = Double(min(9, max(2, count / 14 + 2)))
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
        view.backgroundColor = .black
        view.antialiasingMode = .multisampling2X
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
        context.coordinator.tokens = tokens
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
        private var shardContainer: SCNNode?
        private var selectedBead: SCNNode?

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

            cameraNode.camera = SCNCamera()
            cameraNode.position = SCNVector3(0, 0, 3.2)
            scene.rootNode.addChildNode(cameraNode)

            let ambient = SCNNode()
            ambient.light = SCNLight()
            ambient.light?.type = .ambient
            ambient.light?.intensity = 650
            scene.rootNode.addChildNode(ambient)

            let key = SCNNode()
            key.light = SCNLight()
            key.light?.type = .omni
            key.light?.intensity = 900
            key.position = SCNVector3(2, 3, 4)
            scene.rootNode.addChildNode(key)

            buildGlobe()
            scene.rootNode.addChildNode(globeNode)
            return scene
        }

        private func buildGlobe() {
            globeNode.childNodes.forEach { $0.removeFromParentNode() }
            beadPositions.removeAll()

            let positions = GlobeLayout.positions(count: tokens.count)

            // Glass shell: transparent, non-depth-writing so interior beads and
            // the back of the sphere stay visible through it.
            let shell = SCNSphere(radius: 0.97)
            shell.segmentCount = 64
            let glass = SCNMaterial()
            glass.diffuse.contents = UIColor(white: 0.78, alpha: 1)
            glass.transparency = 0.10
            glass.lightingModel = .blinn
            glass.isDoubleSided = true
            glass.writesToDepthBuffer = false
            shell.firstMaterial = glass
            let shellNode = SCNNode(geometry: shell)
            shellNode.renderingOrder = 10 // draw after beads so it blends over them
            globeNode.addChildNode(shellNode)

            // Ribbon: a single neutral line strip threading the chosen path. Color
            // lives on the beads; the thread just shows the order of decisions.
            if positions.count > 1 {
                globeNode.addChildNode(makeRibbon(positions))
            }

            // Beads, one per token, colored by confidence; forks get a red moon.
            for (i, token) in tokens.enumerated() {
                let pos = positions[i]
                beadPositions[token.step] = pos

                let radius = 0.018 + 0.014 * CGFloat(min(1, token.entropy / TokenVisuals.entropyReferenceMax))
                let bead = SCNSphere(radius: radius)
                let mat = SCNMaterial()
                mat.diffuse.contents = UIColor(TokenVisuals.confidenceColor(token.selectedProbability))
                mat.lightingModel = .constant
                bead.firstMaterial = mat
                let node = SCNNode(geometry: bead)
                node.position = pos
                node.name = "bead:\(token.step)"
                globeNode.addChildNode(node)

                if token.divergedFromGreedy {
                    let moon = SCNSphere(radius: 0.012)
                    let moonMat = SCNMaterial()
                    moonMat.diffuse.contents = UIColor.systemRed
                    moonMat.lightingModel = .constant
                    moon.firstMaterial = moonMat
                    let moonNode = SCNNode(geometry: moon)
                    moonNode.position = v_add(pos, v_scale(v_norm(pos), 0.045))
                    moonNode.name = "bead:\(token.step)" // tappable as the same token
                    globeNode.addChildNode(moonNode)
                }
            }
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
            mat.diffuse.contents = UIColor(white: 1, alpha: 0.4)
            mat.lightingModel = .constant
            geometry.firstMaterial = mat
            return SCNNode(geometry: geometry)
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
                SCNTransaction.commit()
            } else {
                globeNode.eulerAngles = target
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

            // The token's own text, billboarded just above its bead.
            let label = makeLabelNode(
                TokenVisuals.displayText(token.text),
                color: .white,
                scale: 0.16
            )
            label.position = v_add(pos, v_scale(v_norm(pos), 0.10))
            container.addChildNode(label)

            // Top-k alternatives as shards on a small ring in the bead's tangent
            // plane; the actually-sampled one reads brightest.
            let alts = token.alternatives
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
                    mat.diffuse.contents = alt.isSelected
                        ? UIColor.white
                        : UIColor(white: 1, alpha: 0.45)
                    mat.lightingModel = .constant
                    shard.firstMaterial = mat
                    let shardNode = SCNNode(geometry: shard)
                    shardNode.position = shardPos
                    container.addChildNode(shardNode)

                    let altLabel = makeLabelNode(
                        "\(TokenVisuals.displayText(alt.text)) \(Int((alt.probability * 100).rounded()))%",
                        color: alt.isSelected ? .white : UIColor(white: 1, alpha: 0.6),
                        scale: 0.085
                    )
                    altLabel.position = v_add(shardPos, v_scale(dir, 0.05))
                    container.addChildNode(altLabel)
                }
            }

            globeNode.addChildNode(container)
            shardContainer = container
        }

        /// A camera-facing text label: text rasterized to an image on a plane,
        /// constrained to always billboard toward the viewer.
        private func makeLabelNode(_ text: String, color: UIColor, scale: CGFloat) -> SCNNode {
            let (image, size) = Self.textImage(text, color: color)
            let aspect = size.height > 0 ? size.width / size.height : 1
            let plane = SCNPlane(width: scale * aspect, height: scale)
            let mat = SCNMaterial()
            mat.diffuse.contents = image
            mat.lightingModel = .constant
            mat.isDoubleSided = true
            mat.writesToDepthBuffer = false
            plane.firstMaterial = mat
            let node = SCNNode(geometry: plane)
            node.renderingOrder = 20
            let billboard = SCNBillboardConstraint()
            billboard.freeAxes = .all
            node.constraints = [billboard]
            return node
        }

        private static func textImage(_ text: String, color: UIColor) -> (UIImage, CGSize) {
            let font = UIFont.monospacedSystemFont(ofSize: 48, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
            ]
            let bounds = (text as NSString).size(withAttributes: attrs)
            let pad: CGFloat = 16
            let canvas = CGSize(width: bounds.width + pad * 2, height: bounds.height + pad * 2)
            let renderer = UIGraphicsImageRenderer(size: canvas)
            let image = renderer.image { _ in
                (text as NSString).draw(at: CGPoint(x: pad, y: pad), withAttributes: attrs)
            }
            return (image, canvas)
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
                .searchMode: SCNHitTestSearchMode.closest.rawValue
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
    @State private var activeStep: Int?

    /// Only tokens carrying a distribution map to beads; end-of-stream flush
    /// chunks (no alternatives) are dropped so the globe reflects real decisions.
    private var tokens: [TokenSnapshot] { history.filter(\.isAnalyzed) }

    private var activeToken: TokenSnapshot? {
        tokens.first { $0.step == activeStep } ?? tokens.first
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if tokens.isEmpty {
                emptyState
            } else {
                GlobeSceneView(tokens: tokens, activeStep: $activeStep)
                    .ignoresSafeArea()
                scrubber
                focusedCard
            }

            header
        }
        .statusBarHidden()
        .onAppear { if activeStep == nil { activeStep = tokens.first?.step } }
    }

    // MARK: Chrome

    private var header: some View {
        VStack {
            HStack(alignment: .top) {
                if !tokens.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Decision Globe")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("\(tokens.count) tokens · generation trace")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            Spacer()
        }
    }

    /// Vertical scrubber on the right edge: drag through generation time and the
    /// globe spins the active token to front-center.
    private var scrubber: some View {
        HStack {
            Spacer()
            if tokens.count > 1 {
                Slider(value: stepIndexBinding, in: 0...Double(tokens.count - 1), step: 1)
                    .rotationEffect(.degrees(-90))
                    .frame(width: 220)
                    .tint(.white.opacity(0.7))
                    .padding(.trailing, -78)
            }
        }
        .padding(.trailing, 24)
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
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(TokenVisuals.displayText(token.text))
                            .font(.title3.monospaced().bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Text("\(percent(token.selectedProbability))%")
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(TokenVisuals.confidenceColor(token.selectedProbability))
                    }

                    if token.divergedFromGreedy, let greedy = token.greedyAlternative {
                        Label(
                            "Sampled over greedy “\(TokenVisuals.displayText(greedy.text))” at \(percent(greedy.probability))%",
                            systemImage: "arrow.triangle.branch"
                        )
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.9))
                    }

                    HStack(spacing: 18) {
                        metric("entropy", String(format: "%.2f", token.entropy))
                        metric("margin", "\(percent(token.margin))%")
                        metric("surprise", String(format: "%.2f", -log(max(token.selectedProbability, 1e-6))))
                    }

                    if token.alternatives.count > 1 {
                        Divider().overlay(.white.opacity(0.12))
                        TokenAlternativesList(alternatives: token.alternatives)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: 0.2), value: token.step)
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.9))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
