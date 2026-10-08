import CreatorGeometry
import Testing
@testable import CreatorViewport

/// The view cube's face names are a texture painted on the faces: the atlas they're rasterized into, and the UVs
/// that map them onto the cube so each reads upright and unmirrored from outside.
struct CubeLabelTests {
    // MARK: Atlas

    @Test func theAtlasHasSixDisjointRectsWithInkInsideEach() throws {
        let atlas = try #require(CubeLabelAtlas.rasterize())
        #expect(atlas.pixels.count == atlas.width * atlas.height)
        let rects = try ViewCubeRegion.faces.map { try #require(CubeLabelAtlas.rect(for: $0)) }
        #expect(rects.count == 6)
        for rect in rects {
            #expect(rect.u0 >= 0 && rect.v0 >= 0 && rect.u1 <= 1 && rect.v1 <= 1)
            #expect(rect.u1 > rect.u0 && rect.v1 > rect.v0, "non-empty")
        }
        for (index, rect) in rects.enumerated() {
            for other in rects[(index + 1)...] {
                #expect(!rect.overlaps(other), "\(rect) overlaps \(other)")
            }
        }
        for (face, rect) in zip(ViewCubeRegion.faces, rects) {
            #expect(atlas.inkCount(in: rect) > 200, "\(face.label ?? "?") has ink")
        }
        let inside = rects.reduce(0) { $0 + atlas.inkCount(in: $1) }
        #expect(atlas.pixels.count { $0 > 0 } == inside, "no ink outside the label rects")
        #expect(CubeLabelAtlas.rect(for: .isometric) == nil, "corners and edges have no label")
    }

    /// The bitmap's first row is the top of the text (v grows downward, as in a Metal texture) and the text isn't
    /// mirrored: TOP's T has its crossbar at the top, and LEFT's L has its stem on the left.
    @Test func theAtlasTextIsUprightAndUnmirroredInTextureSpace() throws {
        let atlas = try #require(CubeLabelAtlas.rasterize())
        let topRect = try #require(CubeLabelAtlas.rect(for: .top))
        let top = try #require(atlas.inkBox(in: topRect))
        let tWidth = (top.maxX - top.minX) / 3
        func ink(row: Int, columns: ClosedRange<Int>) -> Int { columns.count { atlas.pixel(x: $0, y: row) > 127 } }
        let crossbar = ink(row: top.minY + 2, columns: top.minX...(top.minX + tWidth))
        let stemFoot = ink(row: top.maxY - 2, columns: top.minX...(top.minX + tWidth))
        #expect(crossbar > 3 * stemFoot, "the T's crossbar (\(crossbar)) is at the top, its stem (\(stemFoot)) below")

        let leftRect = try #require(CubeLabelAtlas.rect(for: .left))
        let left = try #require(atlas.inkBox(in: leftRect))
        let stem = (left.minY...left.maxY).count { atlas.pixel(x: left.minX + 1, y: $0) > 127 }
        #expect(Double(stem) > 0.8 * Double(left.maxY - left.minY), "the L's stem runs down the left side")
    }

    // MARK: Mapping onto the cube

    /// Looking at a face from outside, its text reads left to right along `right` with its top towards `up`, and
    /// `right × up` is the outward normal, so it isn't mirrored. Side faces read with +Z up (the turntable camera
    /// never rolls). TOP has +Y up, as the camera sees it looking down from the front. BOTTOM has −Y up: rolling
    /// under from FRONT (pitch −90°, yaw 0) puts −Y at the top of the screen, so BOTTOM reads upright there.
    @Test(arguments: [
        (ViewCubeRegion.front, Vector3(1, 0, 0), Vector3(0, 0, 1)),
        (ViewCubeRegion.right, Vector3(0, 1, 0), Vector3(0, 0, 1)),
        (ViewCubeRegion.back, Vector3(-1, 0, 0), Vector3(0, 0, 1)),
        (ViewCubeRegion.left, Vector3(0, -1, 0), Vector3(0, 0, 1)),
        (ViewCubeRegion.top, Vector3(1, 0, 0), Vector3(0, 1, 0)),
        (ViewCubeRegion.bottom, Vector3(1, 0, 0), Vector3(0, -1, 0)),
    ])
    func faceTextReadsUprightAndUnmirroredFromOutside(_ face: ViewCubeRegion, _ right: Vector3, _ up: Vector3) throws {
        let vertices = GPUGeometry.cubeVertices(hovered: nil, pose: CameraPose())
        let tile = try #require(ViewCubeCell.all.firstIndex { $0.region == face })
        let corners = Array(vertices[(tile * 6)..<(tile * 6 + 3)])
        let textRight = try #require(Self.gradient(corners) { Double($0.uv.x) }.normalized)
        let textUp = try #require((Self.gradient(corners) { -Double($0.uv.y) }).normalized, "v grows down the text")
        #expect(isClose(textRight, right, tolerance: 1e-4), "\(face.label ?? "?") reads along \(textRight)")
        #expect(isClose(textUp, up, tolerance: 1e-4), "\(face.label ?? "?") has its top towards \(textUp)")
        #expect(isClose(textRight.cross(textUp), face.direction, tolerance: 1e-4), "unmirrored: right × up is the outward normal")
        // The camera that looks straight at the face sees the same directions on screen.
        let pose = face.pose(from: CameraPose())
        #expect(isClose(pose.right, right) && isClose(pose.up, up), "upright from the view-cube camera")
    }

    /// Every tile on a face samples that face's label, and the text box sits inside the face: its centre maps to
    /// the middle of the label and the face's corners fall outside it.
    @Test func everyTileCarriesItsFacesLabelAndTheTextFitsInsideTheFace() throws {
        let vertices = GPUGeometry.cubeVertices(hovered: nil, pose: CameraPose())
        for (index, cell) in ViewCubeCell.all.enumerated() {
            let face = try #require(ViewCubeRegion.faces.first { $0.direction.dot(cell.normal) > 0.999 })
            let rect = try #require(CubeLabelAtlas.rect(for: face))
            for vertex in vertices[(index * 6)..<(index * 6 + 6)] {
                #expect(vertex.labelRect == rect.simd)
            }
        }
        for face in ViewCubeRegion.faces {
            let centre = try #require(CubeLabelMapping.uv(of: face.direction, on: face))
            #expect(abs(centre.x - 0.5) < 1e-6 && abs(centre.y - 0.5) < 1e-6)
            let axes = try #require(CubeLabelMapping.axes(of: face))
            let corner = try #require(CubeLabelMapping.uv(of: face.direction + axes.right + axes.up, on: face))
            #expect(corner.x > 1 && corner.y < 0, "the face's top-right corner is past the text's top-right")
        }
        #expect(CubeLabelMapping.axes(of: .isometric) == nil)
    }

    /// The world direction in which `value` grows across the plane of three vertices.
    static func gradient(_ corners: [CubeVertex], _ value: (CubeVertex) -> Double) -> Vector3 {
        func vector(_ v: SIMD3<Float>) -> Vector3 { Vector3(Double(v.x), Double(v.y), Double(v.z)) }
        let e1 = vector(corners[1].position - corners[0].position)
        let e2 = vector(corners[2].position - corners[0].position)
        let d1 = value(corners[1]) - value(corners[0])
        let d2 = value(corners[2]) - value(corners[0])
        let (a, b, c) = (e1.dot(e1), e1.dot(e2), e2.dot(e2))
        let det = a * c - b * b
        let alpha = (d1 * c - d2 * b) / det
        let beta = (d2 * a - d1 * b) / det
        return e1 * alpha + e2 * beta
    }
}
