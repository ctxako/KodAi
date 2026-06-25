//
//  SplashView.swift
//  kodAI_chatbot_dev
//
//  Kodai launch splash — the wolf mark rendered as a 3D SceneKit point cloud,
//  baked from the web piece (hero-wolf-3d.html → wolf-points.json).
//
//  Static render, fitted to the screen, no user camera control. ENTER continues.
//

import SwiftUI
import SceneKit

// MARK: - Baked point data (wolf-points.json in the bundle)

private struct WolfPoints: Decodable {
    let count: Int
    let scale: Float
    let pos: [Float]   // x,y,z × count   (model space, ~±1.2)
    let col: [Float]   // r,g,b × count
    let eye: [Int]     // 0/1   × count
}

private func loadWolfPoints() -> WolfPoints? {
    guard let url = Bundle.main.url(forResource: "wolf-points", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let pts = try? JSONDecoder().decode(WolfPoints.self, from: data)
    else {
        print("⚠️ SplashView: wolf-points.json not found — splash empty (app still works).")
        return nil
    }
    return pts
}

// MARK: - Soft round sprite so each point reads as a glint, not a square

private func glowSprite(_ d: CGFloat = 64) -> UIImage {
    UIGraphicsImageRenderer(size: CGSize(width: d, height: d)).image { ctx in
        let c = ctx.cgContext
        let mid = CGPoint(x: d / 2, y: d / 2)
        let colors = [UIColor.white.withAlphaComponent(1.0).cgColor,
                      UIColor.white.withAlphaComponent(0.85).cgColor,
                      UIColor.white.withAlphaComponent(0.16).cgColor,
                      UIColor.white.withAlphaComponent(0.0).cgColor] as CFArray
        let locs: [CGFloat] = [0, 0.25, 0.6, 1.0]
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: locs) {
            c.drawRadialGradient(g, startCenter: mid, startRadius: 0,
                                 endCenter: mid, endRadius: d / 2, options: [])
        }
    }
}

// MARK: - Point-cloud geometry (returns the node + its bounding radius for fitting)

private func makeWolfNode(_ pts: WolfPoints) -> (node: SCNNode, radius: Float) {
    var vertices = [SCNVector3](); vertices.reserveCapacity(pts.count)
    var colors   = [SIMD4<Float>](); colors.reserveCapacity(pts.count)
    var radius: Float = 0.0001

    for i in 0..<pts.count {
        let p = i * 3
        let x = pts.pos[p], y = pts.pos[p + 1], z = pts.pos[p + 2]
        vertices.append(SCNVector3(x, y, z))
        radius = max(radius, sqrtf(x * x + y * y + z * z))
        colors.append(SIMD4<Float>(min(1.3, pts.col[p]),
                                   min(1.3, pts.col[p + 1]),
                                   min(1.35, pts.col[p + 2]),
                                   1))
    }

    let vSource = SCNGeometrySource(vertices: vertices)

    let colorData = colors.withUnsafeBytes { Data($0) }
    let cSource = SCNGeometrySource(
        data: colorData, semantic: .color,
        vectorCount: colors.count, usesFloatComponents: true,
        componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size,
        dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)

    let indices = Array(UInt32(0)..<UInt32(pts.count))
    let idxData = indices.withUnsafeBytes { Data($0) }
    let element = SCNGeometryElement(
        data: idxData, primitiveType: .point,
        primitiveCount: pts.count, bytesPerIndex: MemoryLayout<UInt32>.size)
    element.pointSize = 0.02
    element.minimumPointScreenSpaceRadius = 1.0
    element.maximumPointScreenSpaceRadius = 6.0

    let geo = SCNGeometry(sources: [vSource, cSource], elements: [element])

    let mat = SCNMaterial()
    mat.lightingModel = .constant            // unlit — colour comes from the data/sprite
    mat.diffuse.contents = glowSprite()
    mat.blendMode = .add                     // additive glow on the dark bg
    mat.writesToDepthBuffer = false
    mat.isDoubleSided = true
    geo.materials = [mat]

    return (SCNNode(geometry: geo), radius)
}

// MARK: - SCNView that fits the wolf to the frame (no user control)

private final class FittedSCNView: SCNView {
    weak var cameraNode: SCNNode?
    var fitRadius: Float = 1.8

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let cam = cameraNode?.camera, bounds.height > 1 else { return }
        let aspect = Float(bounds.width / bounds.height)
        let vHalf = Float(cam.fieldOfView) * .pi / 180 / 2     // fov is vertical (set below)
        let r = fitRadius / 0.82                               // ~18% margin
        let dV = r / tanf(vHalf)
        let dH = r / (tanf(vHalf) * max(aspect, 0.0001))       // portrait → width-limited
        cameraNode?.position = SCNVector3(0, 0, max(dV, dH))
    }
}

private struct WolfSceneView: UIViewRepresentable {
    func makeUIView(context: Context) -> FittedSCNView {
        let v = FittedSCNView()
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        v.allowsCameraControl = false       // no drag-to-inspect
        v.rendersContinuously = true

        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        if let pts = loadWolfPoints() {
            let (wolf, radius) = makeWolfNode(pts)
            scene.rootNode.addChildNode(wolf)
            v.fitRadius = radius
        }

        let cam = SCNCamera()
        cam.fieldOfView = 42
        cam.projectionDirection = .vertical   // fov measured vertically → fit math is deterministic
        cam.zNear = 0.1
        cam.zFar = 100
        let camNode = SCNNode()
        camNode.camera = cam
        camNode.position = SCNVector3(0, 0, 7)   // refined precisely in layoutSubviews
        scene.rootNode.addChildNode(camNode)
        v.cameraNode = camNode

        v.scene = scene
        return v
    }

    func updateUIView(_ uiView: FittedSCNView, context: Context) {}
}

// MARK: - Splash (static, fitted)

struct SplashView: View {
    var onDone: () -> Void = {}

    var body: some View {
        ZStack {
            Color(red: 0.016, green: 0.027, blue: 0.059).ignoresSafeArea()  // #04070f
            WolfSceneView().ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 10) {
                    Text("kodAI")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .tracking(1)

                    Text("Watch a mind decide.")
                        .font(.system(.headline, design: .serif))
                        .foregroundStyle(.white.opacity(0.82))

                    Text("A microscope for language models. Type a prompt and\nwatch it choose every word — on your phone, offline.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.55))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 32)

                Button { onDone() } label: {
                    Text("Begin →")
                        .font(.system(.subheadline, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.vertical, 12)
                        .padding(.horizontal, 28)
                        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
                }
                .padding(.top, 28)
                .padding(.bottom, 48)
            }
        }
    }
}

#Preview {
    SplashView().preferredColorScheme(.dark)
}
