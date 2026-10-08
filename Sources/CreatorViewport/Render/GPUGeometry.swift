import CreatorGeometry
import CreatorKernel
import Foundation

/// Turns meshes, handles and widgets into the GPU structs the shaders read. Pure, so it's tested without a GPU.
enum GPUGeometry {
    static func float3(_ v: Vector3) -> SIMD3<Float> { SIMD3(Float(v.x), Float(v.y), Float(v.z)) }

    /// Three vertices per triangle, each carrying its face. A triangle with an out-of-range index is skipped.
    static func meshVertices(_ mesh: DisplayMesh) -> [MeshVertex] {
        let triangles = min(mesh.indices.count / 3, mesh.triangleFaces.count)
        var vertices: [MeshVertex] = []
        vertices.reserveCapacity(triangles * 3)
        for triangle in 0..<triangles {
            let corners = (0..<3).map { Int(mesh.indices[3 * triangle + $0]) }
            guard corners.allSatisfy({ $0 < mesh.positions.count && $0 < mesh.normals.count }) else { continue }
            let face = UInt32(clamping: mesh.triangleFaces[triangle].rawValue)
            for corner in corners {
                vertices.append(MeshVertex(position: float3(mesh.positions[corner]), normal: float3(mesh.normals[corner]), face: face))
            }
        }
        return vertices
    }

    /// One instance per polyline segment, in edge-ID order. Selected edges are in the selection colour (pink in
    /// Dracula) and twice as wide (spec §6.3). With `selectedOnly`, only selected edges are kept ("Shaded" mode
    /// still shows the rule's edges).
    static func edgeInstances(_ polylines: [EdgeID: [Vector3]], solid: Int, selected: Set<EdgeID>,
                              selectedOnly: Bool, scale: Float, palette: ViewportPalette = .dracula) -> [LineInstance] {
        var instances: [LineInstance] = []
        for edge in polylines.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            let isSelected = selected.contains(edge)
            guard isSelected || !selectedOnly, let points = polylines[edge], points.count >= 2 else { continue }
            let id = PickID.encode(.edge(solid: solid, edge)) ?? 0
            let color = isSelected ? palette.selection : palette.edge
            let width = (isSelected ? 2.5 : 1.25) * scale
            for (a, b) in zip(points, points.dropFirst()) {
                instances.append(LineInstance(a: float3(a), b: float3(b), color: color, width: width, id: id))
            }
        }
        return instances
    }

    /// A shaft from the anchor to the knob, and a square knob, in the handle's category colour.
    static func handleInstances(_ handles: [ViewportHandle], scale: Float, palette: ViewportPalette = .dracula) -> [LineInstance] {
        handles.flatMap { handle -> [LineInstance] in
            let color = handle.tint == .feature ? palette.feature : palette.solid
            let anchor = float3(handle.anchor)
            let knob = float3(handle.knob)
            return [LineInstance(a: anchor, b: knob, color: color, width: 2 * scale, id: 0),
                    LineInstance(a: knob, b: knob, color: color, width: 10 * scale, id: 0),
            ]
        }
    }

    /// The triad's three axes in widget units.
    static func triadInstances(scale: Float, palette: ViewportPalette = .dracula) -> [LineInstance] {
        let length = Float(TriadLayout.axisLength)
        let axes: [(SIMD3<Float>, SIMD4<Float>)] = [
            (SIMD3(length, 0, 0), palette.axisX), (SIMD3(0, length, 0), palette.axisY), (SIMD3(0, 0, length), palette.axisZ),
        ]
        return axes.map { LineInstance(a: .zero, b: $0.0, color: $0.1, width: 2 * scale, id: 0) }
    }

    /// Two triangles per tile. Face centres are lighter than edges and corners, and tiles facing the camera are
    /// brighter. The focus colour (cyan in Dracula) marks the hovered region and the active one, the region the camera looks straight from
    /// (spec §6.6: "view-cube hover and active face").
    ///
    /// Every tile also carries its face's name: the name's atlas rect and each corner's place in the face's text
    /// box (`CubeLabelMapping`). The text box spans most of the face, so it runs across the face's edge and corner
    /// tiles too; a name confined to the centre tile (a third of the face) would be too small to read.
    static func cubeVertices(hovered: ViewCubeRegion?, pose: CameraPose, palette: ViewportPalette = .dracula) -> [CubeVertex] {
        var vertices: [CubeVertex] = []
        vertices.reserveCapacity(ViewCubeCell.all.count * 6)
        let toEye = pose.toEye
        for cell in ViewCubeCell.all {
            let base: SIMD4<Float>
            let light: Float
            if cell.region == hovered || cell.region.direction.dot(toEye) > activeRegionCosine {
                base = palette.hover
                light = 1
            } else {
                base = cell.region.kind == .face ? palette.cubeFace : palette.cubeRim
                light = Float(0.7 + 0.3 * max(0, cell.normal.dot(pose.toEye)))
            }
            let color = SIMD4<Float>(base.x * light, base.y * light, base.z * light, 1)
            let face = ViewCubeRegion.faces.first { $0.direction.dot(cell.normal) > 0.999 }
            let labelRect = face.flatMap(CubeLabelAtlas.rect(for:))?.simd ?? .zero
            for index in [0, 1, 2, 0, 2, 3] {
                let corner = cell.corners[index]
                let uv = face.flatMap { CubeLabelMapping.uv(of: corner, on: $0) } ?? .zero
                vertices.append(CubeVertex(position: float3(corner), color: color, uv: uv, labelRect: labelRect))
            }
        }
        return vertices
    }

    /// A region is active when the view direction is within about 0.5° of it.
    static let activeRegionCosine = 0.99996

    /// One entry per face: bit 1 hovered, bit 2 selected. IDs outside `count` are ignored.
    static func faceFlags(count: Int, hovered: FaceID?, selected: Set<FaceID>) -> [UInt32] {
        var flags = [UInt32](repeating: 0, count: max(count, 0))
        if let hovered, flags.indices.contains(hovered.rawValue) { flags[hovered.rawValue] |= 1 }
        for face in selected where flags.indices.contains(face.rawValue) { flags[face.rawValue] |= 2 }
        return flags
    }

    static func frameUniforms(_ pose: CameraPose, size: ViewportSize, sceneRadius: Double, pixelWidth: Int,
                              pixelHeight: Int) -> FrameUniforms {
        let view = CameraMath.view(pose)
        let viewProjection = CameraMath.projection(pose, aspect: size.aspect, sceneRadius: sceneRadius) * view
        return FrameUniforms(viewProjection: viewProjection.float, view: view.float, eye: float3(pose.eye),
                             forward: float3(-pose.toEye), viewportPixels: SIMD2(Float(pixelWidth), Float(pixelHeight)),
                             isOrthographic: pose.projection == .orthographic ? 1 : 0, padding: 0)
    }

    /// A grid square around the target, snapped to major lines so it doesn't swim while panning, and large
    /// enough to reach the horizon.
    static func gridUniforms(_ frame: ViewportFrame) -> GridUniforms {
        let spacing = frame.gridSpacing
        let major = spacing * 10
        let center = SIMD2<Float>(Float((frame.pose.target.x / major).rounded() * major),
                                  Float((frame.pose.target.y / major).rounded() * major))
        let extent = max(frame.pose.visibleHeight * 6, frame.sceneRadius * 6, major * 2)
        return GridUniforms(center: center, extent: Float(extent), spacing: Float(spacing),
                            minorColor: frame.palette.gridMinor, majorColor: frame.palette.gridMajor)
    }
}
