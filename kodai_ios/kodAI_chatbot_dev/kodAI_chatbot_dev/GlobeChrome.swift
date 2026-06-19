//
//  GlobeChrome.swift
//  kodAI_chatbot_dev
//
//  Shared globe treatment for the Token Globe and the Thread Atlas. The
//  camera-facing ring traces the sphere's outline without filling its interior.
//

import SceneKit
import SwiftUI
import UIKit

enum GlobeChrome {
    static let cyan = UIColor(red: 0.22, green: 0.88, blue: 1.0, alpha: 1)
    static let violet = UIColor(red: 0.55, green: 0.43, blue: 1.0, alpha: 1)
    static let rose = UIColor(red: 0.96, green: 0.38, blue: 0.69, alpha: 1)

    /// A wire-only shell that gives the data a shared coordinate system without
    /// placing a translucent surface between the camera and the marks.
    static func wireShell(radius: Float, latitudeCount: Int = 7, longitudeCount: Int = 12) -> SCNNode {
        let container = SCNNode()

        for latitude in 1..<latitudeCount {
            let polar = Float(latitude) / Float(latitudeCount) * .pi
            let y = radius * cos(polar)
            let ringRadius = radius * sin(polar)
            let points = circlePoints(radius: ringRadius, y: y, segments: 96)
            container.addChildNode(lineNode(points: points, color: cyan, alpha: latitude == latitudeCount / 2 ? 0.22 : 0.10))
        }

        for longitude in 0..<longitudeCount {
            let angle = Float(longitude) / Float(longitudeCount) * .pi
            var points: [SCNVector3] = []
            points.reserveCapacity(97)
            for segment in 0...96 {
                let polar = Float(segment) / 96 * 2 * .pi
                let x = radius * sin(polar) * cos(angle)
                let y = radius * cos(polar)
                let z = radius * sin(polar) * sin(angle)
                points.append(SCNVector3(x, y, z))
            }
            let color = longitude.isMultiple(of: 3) ? rose : violet
            container.addChildNode(lineNode(points: points, color: color, alpha: longitude.isMultiple(of: 3) ? 0.10 : 0.075))
        }

        container.renderingOrder = -20
        return container
    }

    /// A camera-facing circle the size of the globe's silhouette. Attach to the
    /// scene root (not the rotating globe) so it stays put as the globe turns.
    static func silhouetteRing(radius: Float, segments: Int = 96) -> SCNNode {
        let node = SCNNode()
        let inner = lineNode(
            points: cameraCirclePoints(radius: radius, segments: segments),
            color: cyan,
            alpha: 0.72
        )
        let aura = lineNode(
            points: cameraCirclePoints(radius: radius + 0.012, segments: segments),
            color: violet,
            alpha: 0.22
        )
        node.addChildNode(aura)
        node.addChildNode(inner)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        node.constraints = [billboard]
        node.renderingOrder = 30
        return node
    }

    private static func circlePoints(radius: Float, y: Float = 0, segments: Int) -> [SCNVector3] {
        (0...segments).map { segment in
            let angle = Float(segment) / Float(segments) * 2 * .pi
            return SCNVector3(radius * cos(angle), y, radius * sin(angle))
        }
    }

    private static func cameraCirclePoints(radius: Float, segments: Int) -> [SCNVector3] {
        (0...segments).map { segment in
            let angle = Float(segment) / Float(segments) * 2 * .pi
            return SCNVector3(radius * cos(angle), radius * sin(angle), 0)
        }
    }

    static func lineNode(points: [SCNVector3], color: UIColor, alpha: CGFloat) -> SCNNode {
        let source = SCNGeometrySource(vertices: points)
        var indices: [Int32] = []
        for index in 0..<(points.count - 1) {
            indices.append(Int32(index))
            indices.append(Int32(index + 1))
        }
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = color.withAlphaComponent(alpha)
        material.lightingModel = .constant
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = false
        geometry.firstMaterial = material
        return SCNNode(geometry: geometry)
    }
}

/// SwiftUI atmosphere behind either SceneKit globe. The horizon sweep evokes a
/// scanning instrument while remaining quiet enough for labels and controls.
struct GlobeObservatoryBackdrop: View {
    var body: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color(red: 0.06, green: 0.42, blue: 0.64).opacity(0.24),
                    Color(red: 0.08, green: 0.12, blue: 0.24).opacity(0.10),
                    .clear,
                ],
                center: .center,
                startRadius: 12,
                endRadius: 240
            )

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color.cyan.opacity(0.46), Color.blue.opacity(0.76), Color.cyan.opacity(0.46), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .shadow(color: Color.cyan.opacity(0.55), radius: 9)
                .opacity(0.55)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
