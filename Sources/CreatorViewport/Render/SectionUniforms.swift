import Foundation

/// One corner of a cap triangle (`SectionVertex` in `SectionShaders`, pinned by `GPUDataTests`): `xyz` is the position.
struct SectionVertex: Equatable {
    var position: SIMD4<Float>
}

/// One cap's draw settings for the shaders (`SectionUniforms` in `SectionShaders`, stride pinned by `GPUDataTests`).
/// - `origin`, `axisU` and `axisV` are the section plane's origin and axes, the hatch's frame.
/// - `hatchParams` is the spacing and line width (mm) and the cosine and sine of the hatch angle.
/// - `depthParams.x` is how far (mm) the cap's vertices move towards the eye so the cap wins against a coplanar face.
struct SectionUniforms: Equatable {
    var fill: SIMD4<Float>
    var hatch: SIMD4<Float>
    var origin: SIMD4<Float>
    var axisU: SIMD4<Float>
    var axisV: SIMD4<Float>
    var hatchParams: SIMD4<Float>
    var depthParams: SIMD4<Float>
}

extension SectionVertex {
    /// The corners of `cap`'s triangles, three per triangle. A triangle with an index outside `positions` is skipped whole, so the
    /// triangles after it keep their corners.
    static func vertices(of cap: ViewportSection.Cap) -> [SectionVertex] {
        var vertices: [SectionVertex] = []
        vertices.reserveCapacity(cap.triangles.count)
        for start in stride(from: 0, to: cap.triangles.count - 2, by: 3) {
            let corners = cap.triangles[start..<start + 3].map(Int.init)
            guard corners.allSatisfy({ $0 < cap.positions.count }) else { continue }
            for corner in corners { vertices.append(SectionVertex(position: SIMD4(GPUGeometry.float3(cap.positions[corner]), 1))) }
        }
        return vertices
    }
}

extension SectionUniforms {
    /// A cap's draw settings: the palette's colours, the plane's frame, the hatch at `angle` (stripes a fixed number of points wide)
    /// and the `depthBias` (mm) the cap moves towards the eye.
    init(_ section: ViewportSection, angle: Double, frame: ViewportFrame, depthBias: Float) {
        let millimetres = Float(CameraMath.millimetresPerPoint(frame.pose, size: frame.size))
        self.init(
            fill: frame.palette.sectionFill, hatch: frame.palette.sectionHatch,
            origin: SIMD4(GPUGeometry.float3(section.plane.origin), 0),
            axisU: SIMD4(GPUGeometry.float3(section.plane.xAxis), 0),
            axisV: SIMD4(GPUGeometry.float3(section.plane.yAxis), 0),
            hatchParams: SIMD4(Float(ViewportSection.hatchSpacingPoints) * millimetres,
                               Float(ViewportSection.hatchLinePoints) * millimetres,
                               Float(cos(angle)), Float(sin(angle))),
            depthParams: SIMD4(depthBias, 0, 0, 0))
    }
}

extension GPUGeometry {
    /// The line instances of a section's cap outlines, `width` wide, in the palette's section edge colour. They are not pickable.
    static func sectionOutlineInstances(_ section: ViewportSection, width: Float, palette: ViewportPalette) -> [LineInstance] {
        section.caps.flatMap(\.outlines).flatMap { outline in
            zip(outline, outline.dropFirst()).map { a, b in
                LineInstance(a: float3(a), b: float3(b), color: palette.sectionEdge, width: width, id: 0)
            }
        }
    }
}
