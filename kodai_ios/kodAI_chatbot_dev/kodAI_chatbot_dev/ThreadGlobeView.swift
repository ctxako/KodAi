//
//  ThreadGlobeView.swift
//  kodAI_chatbot_dev
//
//  "Thread Atlas" — the whole conversation wrapped onto a clear glass globe.
//  Each traced user→assistant exchange becomes a *continent*: a region whose size
//  approximates its share of context capacity (stable as the thread grows — new
//  continents are added, existing ones never resize). A continent's tint is its
//  mean raw token probability; raw-argmax deviations glow.
//
//  Only what you're looking at is drawn in full: the focused continent scatters
//  its tokens; the others stay cheap glow regions, the far side faint through
//  the glass. A toggleable "vine" threads the continents in conversation order.
//  Drilling into a continent opens the per-response vessel globe (GlobeView),
//  so the atlas (overview) and the trace (detail) are two zoom levels of one idea.
//
//  Phase 2 milestone 2A. Per-token vessels inside a continent and pinch-zoom LOD
//  tiers build on this; today the near zoom is the drill-through to GlobeView.
//

import KodaiKernel
import SceneKit
import SwiftUI
import UIKit

// MARK: - Vector helpers (file-local; mirror GlobeView's set)

private func v_add(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
    SCNVector3(a.x + b.x, a.y + b.y, a.z + b.z)
}
private func v_sub(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
    SCNVector3(a.x - b.x, a.y - b.y, a.z - b.z)
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

/// A point at angular distance `angle` from unit center `c`, in the tangent
/// direction `phi`. Stays on the unit sphere — used to scatter a continent's
/// tokens inside its cap and to seat the continent itself.
private func pointOnSphere(center c: SCNVector3, angle: Float, phi: Float, basis: (SCNVector3, SCNVector3)) -> SCNVector3 {
    let (u, w) = basis
    let tangent = v_add(v_scale(u, cos(phi)), v_scale(w, sin(phi)))
    return v_add(v_scale(c, cos(angle)), v_scale(tangent, sin(angle)))
}

/// Tangent basis (u, w) at a unit position, used to fan points across the
/// surface without lining up on a seam.
private func tangentBasis(at n: SCNVector3) -> (SCNVector3, SCNVector3) {
    var u = v_cross(n, SCNVector3(0, 1, 0))
    if v_len(u) < 1e-3 { u = v_cross(n, SCNVector3(1, 0, 0)) }
    u = v_norm(u)
    return (u, v_norm(v_cross(n, u)))
}

// MARK: - Continent model

/// One conversation exchange (prompt + its analyzed response) placed on the globe.
struct GlobeContinent: Identifiable {
    let id: UUID
    let order: Int
    let promptSummary: String
    let responsePreview: String
    let tokens: [TokenSnapshot]
    /// Estimated exchange footprint relative to context capacity (0–1). The user
    /// prompt uses a lightweight estimator; response tokens are captured exactly.
    let estimatedContextShare: Double
    let avgRawProbability: Float
    let rawArgmaxDifferenceCount: Int

    /// Walks the thread, pairing each analyzed assistant reply with the prompt
    /// that preceded it. Replies with no captured distribution are skipped.
    static func build(messages: [ChatMessage], histories: [UUID: [TokenSnapshot]], contextSize: Int) -> [GlobeContinent] {
        let capacity = max(contextSize, 1)
        var result: [GlobeContinent] = []
        var lastPrompt = ""
        var order = 0

        for message in messages {
            if message.role == .user {
                lastPrompt = message.text
            } else if message.role == .assistant {
                let tokens = (histories[message.id] ?? []).filter(\.isAnalyzed)
                guard !tokens.isEmpty else { continue }

                let exchangeTokens = TokenEstimator.estimate(lastPrompt) + tokens.count
                let avg = tokens.reduce(Float(0)) { $0 + $1.selectedProbability } / Float(tokens.count)
                let rawArgmaxDifferences = tokens.filter(\.differsFromRawArgmax).count

                result.append(
                    GlobeContinent(
                        id: message.id,
                        order: order,
                        promptSummary: snippet(lastPrompt, fallback: "Opening"),
                        responsePreview: snippet(message.text, fallback: "Response"),
                        tokens: tokens,
                        estimatedContextShare: min(max(Double(exchangeTokens) / Double(capacity), 0), 1),
                        avgRawProbability: avg,
                        rawArgmaxDifferenceCount: rawArgmaxDifferences
                    )
                )
                order += 1
            }
        }
        return result
    }

    private static func snippet(_ text: String, fallback: String) -> String {
        let trimmed = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if trimmed.isEmpty { return fallback }
        return trimmed.count > 42 ? String(trimmed.prefix(42)) + "…" : trimmed
    }
}

// MARK: - Scene host

private struct ThreadGlobeSceneView: UIViewRepresentable {
    let continents: [GlobeContinent]
    @Binding var focusedOrder: Int
    @Binding var selectedTokenStep: Int?
    let vineOn: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            continents: continents,
            onSelectContinent: { order in
                focusedOrder = order
                selectedTokenStep = nil
            },
            onSelectToken: { step in selectedTokenStep = step }
        )
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.scene = context.coordinator.buildScene()
        view.pointOfView = context.coordinator.cameraNode

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(pinch)
        context.coordinator.scnView = view

        context.coordinator.setVine(visible: vineOn)
        if let first = continents.first {
            context.coordinator.focus(order: first.order, animated: false)
        }
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        context.coordinator.setVine(visible: vineOn)
        if focusedOrder != context.coordinator.currentOrder {
            context.coordinator.focus(order: focusedOrder, animated: !UIAccessibility.isReduceMotionEnabled)
        }
        context.coordinator.syncTokenSelection(selectedTokenStep)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject {
        private let continents: [GlobeContinent]
        private let onSelectContinent: (Int) -> Void
        private let onSelectToken: (Int) -> Void

        weak var scnView: SCNView?
        let cameraNode = SCNNode()
        private let globeNode = SCNNode()

        private let shellRadius: Float = 0.97
        private var centers: [SCNVector3] = []     // unit vectors, per continent order
        private var caps: [Float] = []             // angular cap radius, per order
        private var glowNodes: [SCNNode] = []      // one per continent (depth-cued)
        private var labelNodes: [SCNNode] = []
        private var detailContainer: SCNNode?      // focused continent's tokens
        private var vineNode: SCNNode?
        private var localStrandNode: SCNNode?      // token-order spiral in the focus
        private var vesselContainer: SCNNode?      // selected token's vessels
        private var tokenPositions: [Int: SCNVector3] = [:]   // step → world pos
        private var selectedTokenBead: SCNNode?
        private(set) var currentTokenStep: Int?

        private var spinYaw: Float = 0
        private var spinPitch: Float = 0
        private var dragYaw: Float = 0
        private var dragPitch: Float = 0
        private(set) var currentOrder: Int = -1

        init(
            continents: [GlobeContinent],
            onSelectContinent: @escaping (Int) -> Void,
            onSelectToken: @escaping (Int) -> Void
        ) {
            self.continents = continents
            self.onSelectContinent = onSelectContinent
            self.onSelectToken = onSelectToken
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
            scene.rootNode.addChildNode(GlobeChrome.silhouetteRing(radius: shellRadius + 0.02))
            return scene
        }

        // MARK: Build

        private func buildGlobe() {
            globeNode.childNodes.forEach { $0.removeFromParentNode() }
            glowNodes.removeAll()
            labelNodes.removeAll()
            detailContainer = nil
            vineNode = nil

            globeNode.addChildNode(GlobeChrome.wireShell(radius: shellRadius))

            // Continent seats: a pole-to-pole spiral so conversation order maps to
            // latitude (north = first), reinforced by the vine.
            centers = continentCenters(count: continents.count)
            caps = continents.map { capAngle(forShare: $0.estimatedContextShare) }

            for continent in continents {
                let center = centers[continent.order]
                let glow = makeRegion(for: continent, center: center)
                glowNodes.append(glow)
                globeNode.addChildNode(glow)

                let label = makeLabel("E\(continent.order + 1)", at: v_scale(center, shellRadius + 0.045), bright: false)
                labelNodes.append(label)
                globeNode.addChildNode(label)
            }

            vineNode = makeVine()
            if let vineNode { globeNode.addChildNode(vineNode) }
        }

        /// Even-ish pole-to-pole spiral of unit vectors (one per continent).
        private func continentCenters(count: Int) -> [SCNVector3] {
            guard count > 0 else { return [] }
            let turns = min(7, max(1.0, sqrt(Double(count)) * 0.9))
            var result: [SCNVector3] = []
            for i in 0..<count {
                let t = count > 1 ? Double(i) / Double(count - 1) : 0.5
                let polar = (0.16 + 0.68 * t) * .pi
                let lon = t * turns * 2 * .pi
                let ring = sin(polar)
                result.append(SCNVector3(Float(ring * cos(lon)), Float(cos(polar)), Float(ring * sin(lon))))
            }
            return result
        }

        /// Angular cap radius whose spherical-cap area equals `share` of the globe,
        /// floored so a one-word reply is still a tappable place, capped so a huge
        /// exchange can't swallow the orb.
        private func capAngle(forShare share: Double) -> Float {
            let s = min(max(share, 0.018), 0.34)
            return Float(acos(1 - 2 * s))
        }

        /// A spherical-cap region whose area carries exchange footprint. Unlike a
        /// separate sphere, this patch conforms to the atlas surface and preserves
        /// the visual identity of a single globe.
        private func makeRegion(for continent: GlobeContinent, center: SCNVector3) -> SCNNode {
            let cap = caps[continent.order]
            let tint = UIColor(TokenVisuals.confidenceColor(continent.avgRawProbability))
            let basis = tangentBasis(at: center)
            let radius = shellRadius + 0.006
            let anchor = v_scale(center, radius)
            let segments = 48
            var vertices = [SCNVector3Zero]
            var boundary: [SCNVector3] = []
            boundary.reserveCapacity(segments + 1)
            for segment in 0...segments {
                let phi = Float(segment) / Float(segments) * 2 * .pi
                let point = v_sub(
                    v_scale(pointOnSphere(center: center, angle: cap, phi: phi, basis: basis), radius),
                    anchor
                )
                boundary.append(point)
                if segment < segments { vertices.append(point) }
            }

            var triangleIndices: [Int32] = []
            for segment in 0..<segments {
                triangleIndices.append(0)
                triangleIndices.append(Int32(segment + 1))
                triangleIndices.append(Int32((segment + 1) % segments + 1))
            }
            let source = SCNGeometrySource(vertices: vertices)
            let element = SCNGeometryElement(indices: triangleIndices, primitiveType: .triangles)
            let geometry = SCNGeometry(sources: [source], elements: [element])
            let material = SCNMaterial()
            material.diffuse.contents = tint.withAlphaComponent(0.13)
            material.emission.contents = tint.withAlphaComponent(0.025)
            material.lightingModel = .constant
            material.blendMode = .alpha
            material.isDoubleSided = true
            material.writesToDepthBuffer = false
            geometry.firstMaterial = material

            let node = SCNNode()
            node.position = anchor
            node.name = "continent:\(continent.order)"
            node.categoryBitMask = 4

            let fillNode = SCNNode(geometry: geometry)
            fillNode.name = node.name
            fillNode.categoryBitMask = 4
            node.addChildNode(fillNode)

            let outline = GlobeChrome.lineNode(points: boundary, color: tint, alpha: 0.76)
            outline.name = node.name
            outline.categoryBitMask = 4
            node.addChildNode(outline)

            // A single gold beacon communicates the exception without turning the
            // whole footprint into an ambiguous yellow region.
            if continent.rawArgmaxDifferenceCount > 0 {
                let markerSize = CGFloat(0.018 + min(0.018, Double(continent.rawArgmaxDifferenceCount) * 0.0004))
                let marker = SCNPyramid(width: markerSize, height: markerSize * 1.35, length: markerSize)
                let markerMaterial = SCNMaterial()
                markerMaterial.diffuse.contents = UIColor(TokenVisuals.divergenceColor)
                markerMaterial.lightingModel = .constant
                marker.firstMaterial = markerMaterial
                let markerNode = SCNNode(geometry: marker)
                markerNode.position = v_scale(center, shellRadius + 0.04 - radius)
                markerNode.eulerAngles.z = .pi / 4
                markerNode.name = node.name
                markerNode.categoryBitMask = 4
                node.addChildNode(markerNode)
            }
            return node
        }

        private func makeLabel(_ text: String, at pos: SCNVector3, bright: Bool) -> SCNNode {
            let geo = SCNText(string: text, extrusionDepth: 0)
            geo.font = .systemFont(ofSize: 8, weight: .semibold)
            geo.flatness = 0.4
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor(white: 1, alpha: bright ? 0.95 : 0.6)
            mat.lightingModel = .constant
            mat.writesToDepthBuffer = false
            geo.firstMaterial = mat
            let node = SCNNode(geometry: geo)
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


        /// A faint strand threading the continent seats in conversation order.
        private func makeVine() -> SCNNode? {
            guard centers.count > 1 else { return nil }
            let verts = centers.map { v_scale($0, shellRadius + 0.012) }
            let source = SCNGeometrySource(vertices: verts)
            var indices: [Int32] = []
            for i in 0..<(verts.count - 1) {
                indices.append(Int32(i)); indices.append(Int32(i + 1))
            }
            let element = SCNGeometryElement(indices: indices, primitiveType: .line)
            let geo = SCNGeometry(sources: [source], elements: [element])
            let mat = SCNMaterial()
            mat.diffuse.contents = GlobeChrome.rose.withAlphaComponent(0.46)
            mat.lightingModel = .constant
            mat.writesToDepthBuffer = false
            geo.firstMaterial = mat
            return SCNNode(geometry: geo)
        }

        func setVine(visible: Bool) {
            vineNode?.isHidden = !visible
            localStrandNode?.isHidden = !visible
        }

        // MARK: Focus + LOD

        func focus(order: Int, animated: Bool) {
            guard continents.indices.contains(order) else { return }
            currentOrder = order
            let center = centers[order]

            let ring = sqrt(center.x * center.x + center.z * center.z)
            spinYaw = -atan2(center.x, center.z)
            spinPitch = atan2(center.y, ring)
            dragYaw = 0
            dragPitch = 0

            applyOrientation(animated: animated)
            rebuildDetail(for: order)
        }

        private func applyOrientation(animated: Bool) {
            let pitch = max(-1.45, min(1.45, spinPitch + dragPitch))
            let target = SCNVector3(pitch, spinYaw + dragYaw, 0)
            if animated {
                SCNTransaction.begin()
                SCNTransaction.animationDuration = 0.6
                SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                globeNode.eulerAngles = target
                SCNTransaction.completionBlock = { [weak self] in self?.updateDepthCues() }
                SCNTransaction.commit()
            } else {
                globeNode.eulerAngles = target
                updateDepthCues()
            }
        }

        /// Back-hemisphere continents fade to a faint outline seen through the
        /// glass; the focused one's glow dims so its scattered tokens read.
        private func updateDepthCues() {
            for (i, node) in glowNodes.enumerated() {
                let z = node.presentation.worldPosition.z
                let base: CGFloat = z < -0.1 ? 0.10 : (z < 0.2 ? 0.38 : 0.72)
                node.opacity = i == currentOrder ? min(1, base * 1.22) : base * 0.62
            }
            for (i, node) in labelNodes.enumerated() {
                let z = node.presentation.worldPosition.z
                let distance = abs(i - currentOrder)
                if z < -0.05 {
                    node.opacity = i == currentOrder ? 0.32 : 0
                } else if i == currentOrder {
                    node.opacity = 1
                } else {
                    node.opacity = distance == 1 ? 0.38 : 0.06
                }
            }
        }

        /// Lays the focused continent's tokens along an order-legible spiral that
        /// winds out from the continent's center — the only place individual tokens
        /// are drawn, so the atlas never turns to confetti. A faint strand threads
        /// them in print order (the local "DNA"); tapping a bead blooms its vessels.
        private func rebuildDetail(for order: Int) {
            detailContainer?.removeFromParentNode()
            localStrandNode?.removeFromParentNode()
            clearTokenSelection()
            tokenPositions.removeAll()
            guard continents.indices.contains(order) else { return }
            let continent = continents[order]
            let center = centers[order]
            let cap = caps[order]
            let basis = tangentBasis(at: center)

            let container = SCNNode()
            let tokens = continent.tokens
            let count = tokens.count
            let turns = min(9.0, max(1.5, sqrt(Double(count)) * 0.6))
            let densityScale = max(0.5, min(1, sqrt(120 / CGFloat(max(count, 1)))))
            var ordered: [SCNVector3] = []
            ordered.reserveCapacity(count)

            for (i, token) in tokens.enumerated() {
                let frac = count > 1 ? Float(i) / Float(count - 1) : 0
                // Monotonic angle out from center + many turns ⇒ a readable spiral.
                let angle = cap * pow(frac, 0.7)
                let phi = frac * Float(turns) * 2 * .pi
                let unit = pointOnSphere(center: center, angle: angle, phi: phi, basis: basis)
                let pos = v_scale(unit, shellRadius + 0.004)
                tokenPositions[token.step] = pos
                ordered.append(pos)

                let radius = densityScale * (0.012 + 0.012 * CGFloat(min(1, token.entropy / TokenVisuals.entropyReferenceMax)))
                let bead = SCNSphere(radius: radius)
                bead.segmentCount = 8
                let mat = SCNMaterial()
                mat.diffuse.contents = UIColor(TokenVisuals.confidenceColor(token.selectedProbability))
                mat.lightingModel = .constant
                bead.firstMaterial = mat
                let node = SCNNode(geometry: bead)
                node.position = pos
                node.name = "token:\(token.step)"
                node.categoryBitMask = 8
                container.addChildNode(node)

                if token.differsFromRawArgmax {
                    let marker = SCNPyramid(width: radius * 1.7, height: radius * 2.2, length: radius * 1.7)
                    let markerMaterial = SCNMaterial()
                    markerMaterial.diffuse.contents = UIColor(TokenVisuals.divergenceColor)
                    markerMaterial.lightingModel = .constant
                    marker.firstMaterial = markerMaterial
                    let markerNode = SCNNode(geometry: marker)
                    markerNode.position = v_add(pos, v_scale(v_norm(pos), Float(radius * 2.1)))
                    markerNode.eulerAngles.z = .pi / 4
                    markerNode.name = "token:\(token.step)"
                    markerNode.categoryBitMask = 8
                    container.addChildNode(markerNode)
                }

                // Preserve delicate beads while giving touch users a practical target.
                let hitTarget = SCNSphere(radius: max(0.04, radius * 2.4))
                let hitMaterial = SCNMaterial()
                hitMaterial.colorBufferWriteMask = []
                hitMaterial.writesToDepthBuffer = false
                hitTarget.firstMaterial = hitMaterial
                let hitNode = SCNNode(geometry: hitTarget)
                hitNode.position = pos
                hitNode.name = "token:\(token.step)"
                hitNode.categoryBitMask = 8
                container.addChildNode(hitNode)
            }

            globeNode.addChildNode(container)
            detailContainer = container

            if ordered.count > 1 {
                let strand = makeStrand(ordered, alpha: 0.4)
                strand.isHidden = vineNode?.isHidden ?? false
                globeNode.addChildNode(strand)
                localStrandNode = strand
            }
        }

        /// A polyline through points in order — used for both the continent vine
        /// and the in-continent token strand.
        private func makeStrand(_ points: [SCNVector3], alpha: CGFloat) -> SCNNode {
            let source = SCNGeometrySource(vertices: points)
            var indices: [Int32] = []
            for i in 0..<(points.count - 1) { indices.append(Int32(i)); indices.append(Int32(i + 1)) }
            let element = SCNGeometryElement(indices: indices, primitiveType: .line)
            let geo = SCNGeometry(sources: [source], elements: [element])
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor(white: 1, alpha: alpha)
            mat.lightingModel = .constant
            mat.writesToDepthBuffer = false
            geo.firstMaterial = mat
            return SCNNode(geometry: geo)
        }

        // MARK: Token selection + vessels

        func syncTokenSelection(_ step: Int?) {
            guard step != currentTokenStep else { return }
            if let step { selectToken(step: step) } else { clearTokenSelection() }
        }

        /// Emphasizes the tapped bead and blooms its considered-but-unchosen
        /// alternatives as vessels — the Phase 1 decision sprig, now in-place.
        private func selectToken(step: Int) {
            clearTokenSelection()
            currentTokenStep = step
            guard let pos = tokenPositions[step],
                  let continent = continents.indices.contains(currentOrder) ? continents[currentOrder] : nil,
                  let token = continent.tokens.first(where: { $0.step == step })
            else { return }

            if let bead = detailContainer?.childNode(withName: "token:\(step)", recursively: false) {
                bead.scale = SCNVector3(2, 2, 2)
                selectedTokenBead = bead
            }

            let container = SCNNode()
            let considered = Array(token.alternatives.filter { !$0.isSelected }.prefix(5))
            if !considered.isEmpty {
                let n = v_norm(pos)
                let (u, w) = tangentBasis(at: n)
                let origin = v_add(pos, v_scale(n, 0.015))
            let rawArgmaxID = token.rawArgmaxAlternative?.tokenID

                for (j, alt) in considered.enumerated() {
                    let angle = Float(j) / Float(considered.count) * 2 * .pi
                    let dir = v_add(v_scale(u, cos(angle)), v_scale(w, sin(angle)))
                    let reach = Float(0.10 + 0.08 * alt.probability)
                    let tip = v_add(v_add(pos, v_scale(n, 0.04)), v_scale(dir, reach))

                    let isRawArgmax = token.differsFromRawArgmax && alt.tokenID == rawArgmaxID
                    let color = isRawArgmax
                        ? UIColor(TokenVisuals.divergenceColor)
                        : UIColor(TokenVisuals.alternativeColor)
                    let opacity: CGFloat = isRawArgmax ? 0.82 : 0.46

                    container.addChildNode(
                        makeVessel(from: origin, to: tip, radius: isRawArgmax ? 0.003 : 0.002, color: color, opacity: opacity)
                    )
                    let dot = SCNSphere(radius: CGFloat(0.005 + 0.015 * alt.probability))
                    dot.segmentCount = 8
                    let dotMat = SCNMaterial()
                    dotMat.diffuse.contents = color.withAlphaComponent(opacity)
                    dotMat.lightingModel = .constant
                    dotMat.writesToDepthBuffer = false
                    dot.firstMaterial = dotMat
                    let dotNode = SCNNode(geometry: dot)
                    dotNode.position = tip
                    container.addChildNode(dotNode)

                    container.addChildNode(makeLabel(vesselLabel(alt), at: v_add(tip, v_scale(n, 0.025)), bright: isRawArgmax))
                }
            }
            globeNode.addChildNode(container)
            vesselContainer = container
        }

        private func clearTokenSelection() {
            vesselContainer?.removeFromParentNode()
            vesselContainer = nil
            selectedTokenBead?.scale = SCNVector3(1, 1, 1)
            selectedTokenBead = nil
            currentTokenStep = nil
        }

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

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .changed else {
                gesture.scale = 1
                return
            }
            let z = cameraNode.position.z / Float(gesture.scale)
            cameraNode.position.z = max(2.1, min(4.6, z))
            gesture.scale = 1
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = scnView else { return }
            let point = gesture.location(in: view)

            // Tokens win over continents so you can pick a bead inside the focus.
            let tokenHits = view.hitTest(point, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .categoryBitMask: 8,
            ])
            for hit in tokenHits {
                if let name = hit.node.name, name.hasPrefix("token:"),
                   let step = Int(name.dropFirst("token:".count)) {
                    onSelectToken(step)
                    return
                }
            }

            let continentHits = view.hitTest(point, options: [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .categoryBitMask: 4,
            ])
            for hit in continentHits {
                var node: SCNNode? = hit.node
                while let n = node {
                    if let name = n.name, name.hasPrefix("continent:"),
                       let order = Int(name.dropFirst("continent:".count)) {
                        onSelectContinent(order)
                        return
                    }
                    node = n.parent
                }
            }
        }
    }
}

// MARK: - Thread Atlas screen

struct ThreadGlobeView: View {
    private let continents: [GlobeContinent]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var focusedOrder = 0
    @State private var vineOn = true
    @State private var selectedTokenStep: Int?
    @State private var exploreTarget: GlobeContinent?
    @State private var isReadingGuideExpanded = false

    init(messages: [ChatMessage], histories: [UUID: [TokenSnapshot]], contextSize: Int) {
        continents = GlobeContinent.build(messages: messages, histories: histories, contextSize: contextSize)
    }

    private var focused: GlobeContinent? {
        continents.indices.contains(focusedOrder) ? continents[focusedOrder] : continents.first
    }

    private var selectedToken: TokenSnapshot? {
        guard let step = selectedTokenStep else { return nil }
        return focused?.tokens.first { $0.step == step }
    }

    var body: some View {
        ZStack {
            LiquidGlassBackground()
            RadialGradient(
                colors: [ChatPalette.accentBlue.opacity(0.14), .clear],
                center: .center, startRadius: 20, endRadius: 330
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                if continents.isEmpty {
                    emptyState.frame(maxHeight: .infinity)
                } else {
                    readingGuide

                    ZStack {
                        GlobeObservatoryBackdrop()
                        ThreadGlobeSceneView(
                            continents: continents,
                            focusedOrder: $focusedOrder,
                            selectedTokenStep: $selectedTokenStep,
                            vineOn: vineOn
                        )
                        .accessibilityHidden(true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 12)
                    .overlay(alignment: .topLeading) { chronologyKey.padding(18) }
                    .overlay(alignment: .bottomTrailing) { vineToggle.padding(20) }

                    scrubber
                    if let token = selectedToken {
                        tokenCard(token)
                    } else {
                        focusedCard
                    }
                }
            }
        }
        .statusBarHidden()
        .onChange(of: focusedOrder) { selectedTokenStep = nil }
        .fullScreenCover(item: $exploreTarget) { continent in
            GlobeView(messageText: continent.responsePreview, history: continent.tokens)
        }
    }

    // MARK: Chrome

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Thread Atlas")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                if !continents.isEmpty {
                    Text("\(continents.count) traced exchanges · earlier at north, later at south")
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
            .accessibilityLabel("Close thread atlas")
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    private var readingGuide: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    isReadingGuideExpanded.toggle()
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.cyan.opacity(0.9))
                    Text("How to read this atlas")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isReadingGuideExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("Chronological map · before-sampling probability is not correctness")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))

            if isReadingGuideExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 14) {
                            rawProbabilityLegend
                            footprintLegend
                            rawArgmaxLegend
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            rawProbabilityLegend
                            footprintLegend
                            rawArgmaxLegend
                        }
                    }

                    Text("Regions follow conversation order, not meaning. A focused region reveals its response tokens; the vine links exchanges from first to latest.")
                        .foregroundStyle(.white.opacity(0.58))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("The \(TokenTraceStore.maxResponsesPerSession) most recent response traces persist after relaunch.")
                        .foregroundStyle(.white.opacity(0.42))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.56))
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rawProbabilityLegend: some View {
        Label {
            Text("color = average chosen-token probability")
        } icon: {
            LinearGradient(
                colors: [TokenVisuals.confidenceColor(0), TokenVisuals.confidenceColor(0.5), TokenVisuals.confidenceColor(1)],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: 18, height: 7)
            .clipShape(Capsule())
        }
    }

    private var footprintLegend: some View {
        Label {
            Text("area = estimated context footprint")
        } icon: {
            HStack(spacing: 2) {
                Circle().fill(.white.opacity(0.55)).frame(width: 4, height: 4)
                Circle().fill(.white.opacity(0.55)).frame(width: 8, height: 8)
            }
        }
    }

    private var rawArgmaxLegend: some View {
        Label {
            Text("gold = includes a non-top choice")
        } icon: {
            Image(systemName: "diamond.fill")
                .foregroundStyle(TokenVisuals.divergenceColor)
                .font(.system(size: 7))
        }
    }

    private var vineToggle: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { vineOn.toggle() }
            Haptics.lightTap()
        } label: {
            Image(systemName: vineOn ? "point.topleft.down.to.point.bottomright.curvepath.fill" : "point.topleft.down.to.point.bottomright.curvepath")
                .font(.body.weight(.semibold))
                .foregroundStyle(vineOn ? ChatPalette.accentBlue : .white.opacity(0.7))
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.1), in: Circle())
        }
        .accessibilityLabel(vineOn ? "Hide conversation thread" : "Show conversation thread")
    }

    private var chronologyKey: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("E1 → E\(continents.count)")
                .foregroundStyle(.white.opacity(0.62))
            Text("first → latest")
        }
        .font(.caption2.monospaced())
        .foregroundStyle(.white.opacity(0.42))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 8))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var scrubber: some View {
        HStack(spacing: 10) {
            stepButton(systemImage: "chevron.left", delta: -1, label: "Previous exchange")
            Slider(
                value: Binding(
                    get: { Double(focusedOrder) },
                    set: { focusedOrder = min(max(0, Int($0.rounded())), continents.count - 1) }
                ),
                in: 0...Double(max(continents.count - 1, 1)),
                step: 1
            )
            .tint(.white.opacity(0.72))
            .accessibilityLabel("Exchange position")
            .accessibilityValue("Exchange \(focusedOrder + 1) of \(continents.count): \(focused?.promptSummary ?? "")")
            stepButton(systemImage: "chevron.right", delta: 1, label: "Next exchange")
            Text("\(focusedOrder + 1)/\(continents.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.55))
                .frame(minWidth: 48, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
    }

    private func stepButton(systemImage: String, delta: Int, label: String) -> some View {
        Button {
            focusedOrder = min(max(0, focusedOrder + delta), continents.count - 1)
            Haptics.lightTap()
        } label: {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.08), in: Circle())
        }
        .foregroundStyle(.white.opacity(0.8))
        .disabled(focusedOrder + delta < 0 || focusedOrder + delta >= continents.count)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var focusedCard: some View {
        if let continent = focused {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Exchange \(continent.order + 1)")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Text("\(percent(continent.avgRawProbability))% avg chosen p")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(TokenVisuals.confidenceColor(continent.avgRawProbability))
                }

                Text(continent.promptSummary)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                Text(continent.responsePreview)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(2)

                HStack(spacing: 18) {
                    metric("\(continent.tokens.count)", "tokens")
                    metric("\(percent(Float(continent.estimatedContextShare)))%", "context footprint")
                    metric("\(continent.rawArgmaxDifferenceCount)/\(continent.tokens.count)", "not top choice")
                }
                .padding(.top, 2)

                Button {
                    exploreTarget = continent
                    Haptics.lightTap()
                } label: {
                    HStack {
                        Text("Open token replay")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .background(ChatPalette.accentBlue.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 2)
                .accessibilityHint("Opens an accessible token-by-token replay with before-sampling probability details")
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlassPanel(
                tint: reduceTransparency ? ChatPalette.elevatedSurface : ChatPalette.elevatedSurface.opacity(0.72),
                cornerRadius: 22
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: continent.id)
        }
    }

    /// Shown in place of the continent summary once a bead is tapped — the same
    /// decision read as the per-response globe, without leaving the atlas.
    @ViewBuilder
    private func tokenCard(_ token: TokenSnapshot) -> some View {
        let index = focused?.tokens.firstIndex { $0.step == token.step } ?? 0
        let total = focused?.tokens.count ?? 0
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button {
                    selectedTokenStep = nil
                    Haptics.lightTap()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .accessibilityLabel("Back to exchange")

                Text(readableToken(token.text))
                    .font(.title3.monospaced().bold())
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer()
                Text("\(percent(token.selectedProbability))% chosen p")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(TokenVisuals.confidenceColor(token.selectedProbability))
            }

            Text("Token \(index + 1) of \(total) in exchange \(focusedOrder + 1)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.43))

            Text(tokenTakeaway(token))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))

            HStack(spacing: 18) {
                metric(String(format: "%.2f", token.entropy), "uncertainty nats")
                metric("\(percent(token.margin))", "top-two gap pp")
                metric(String(format: "%.2f", -log(max(token.selectedProbability, 1e-6))), "surprise nats")
            }
            .padding(.top, 2)
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

    private func tokenTakeaway(_ token: TokenSnapshot) -> String {
        let selected = readableToken(token.text)
        if token.differsFromRawArgmax, let rawArgmax = token.rawArgmaxAlternative {
            return "“\(selected)” was chosen with \(percent(token.selectedProbability))% probability before sampling. The top raw choice was “\(readableToken(rawArgmax.text))” at \(percent(rawArgmax.probability))%; sampler controls determined the emitted token."
        }
        if token.selectedProbability >= 0.75 {
            return "Before sampling, the model strongly favored “\(selected)” at \(percent(token.selectedProbability))%."
        }
        if token.margin < 0.08 {
            return "“\(selected)” was the top raw choice, but the two leading candidates were close."
        }
        return "“\(selected)” was the top raw choice, with other candidates still carrying probability."
    }

    private func readableToken(_ text: String) -> String {
        if text == "\n" { return "newline" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "space" : trimmed
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.caption.monospacedDigit())
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
            Text("No analyzed exchanges in this chat yet.")
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
