//
//  GlobeChrome.swift
//  kodAI_chatbot_dev
//
//  Shared glass treatment for the Token Globe and the Thread Atlas: a clear
//  fresnel shell (nearly invisible face-on, frosting toward the limb so far-side
//  content is veiled) plus a crisp silhouette ring. The ring is an in-scene
//  camera-facing circle, so it traces the sphere's outline exactly at any
//  rotation without projecting from SwiftUI.
//

import SceneKit
import UIKit

enum GlobeChrome {
    /// Clear glass with a fresnel rim. The fragment shader keeps the surface
    /// almost transparent looking straight on and frosts it toward grazing
    /// angles, which both glows the silhouette and veils the back hemisphere.
    static func glassShell(radius: Float) -> SCNNode {
        let sphere = SCNSphere(radius: CGFloat(radius))
        sphere.segmentCount = 64
        let material = SCNMaterial()
        material.lightingModel = .constant
        // Keep the fallback transparent too. If SceneKit cannot compile the
        // shader modifier, the shell must never fall back to an opaque sphere.
        material.diffuse.contents = UIColor.clear
        material.blendMode = .alpha
        material.transparencyMode = .singleLayer
        material.isDoubleSided = false
        material.writesToDepthBuffer = false
        material.shaderModifiers = [.fragment: fresnelFragment]
        sphere.firstMaterial = material
        let node = SCNNode(geometry: sphere)
        // The shell itself stays fully transparent face-on. The shader supplies
        // only a restrained rim; the separate silhouette ring defines the orb.
        node.opacity = 1
        node.renderingOrder = -10
        return node
    }

    private static let fresnelFragment = """
    #pragma transparent
    #pragma body
    float fres = pow(1.0 - abs(dot(normalize(_surface.normal), normalize(_surface.view))), 3.4);
    _output.color.rgb = float3(0.40, 0.54, 0.74);
    _output.color.a = fres * 0.10;
    """

    /// A camera-facing circle the size of the globe's silhouette. Attach to the
    /// scene root (not the rotating globe) so it stays put as the globe turns.
    static func silhouetteRing(radius: Float, segments: Int = 96) -> SCNNode {
        var vertices: [SCNVector3] = []
        vertices.reserveCapacity(segments + 1)
        for i in 0...segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            vertices.append(SCNVector3(radius * cos(a), radius * sin(a), 0))
        }
        let source = SCNGeometrySource(vertices: vertices)
        var indices: [Int32] = []
        for i in 0..<segments { indices.append(Int32(i)); indices.append(Int32(i + 1)) }
        let element = SCNGeometryElement(indices: indices, primitiveType: .line)
        let geometry = SCNGeometry(sources: [source], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor(white: 1, alpha: 0.5)
        material.lightingModel = .constant
        material.writesToDepthBuffer = false
        geometry.firstMaterial = material
        let node = SCNNode(geometry: geometry)
        let billboard = SCNBillboardConstraint()
        billboard.freeAxes = .all
        node.constraints = [billboard]
        node.renderingOrder = 30
        return node
    }
}
