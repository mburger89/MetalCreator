import CreatorGeometry
import CreatorImplicit
import CreatorKernel
import Foundation
import Testing
@testable import CreatorApp

/// Hard edges on display (mesh import spec, "The display: hard edges"): a mesh with a `creaseAngle` is drawn with a vertex per group
/// of faces joined across edges within the angle, so a CAD part's edges stay sharp and a smooth surface stays smooth.
struct MeshDisplayCreaseTests {
    /// A unit-sided box of 8 welded vertices (vertex `x + 2y + 4z`), 12 triangles wound counter-clockwise from outside.
    static func box(creaseAngle: Double?, normals: [SIMD3<Float>] = [], half: Float = 1) -> TriangleMesh {
        let positions = (0..<8).map { corner in
            SIMD3<Float>((corner & 1) == 0 ? -half : half, (corner & 2) == 0 ? -half : half, (corner & 4) == 0 ? -half : half)
        }
        let quads: [[UInt32]] = [[0, 4, 6, 2], [1, 3, 7, 5], [0, 1, 5, 4], [2, 6, 7, 3], [0, 2, 3, 1], [4, 5, 7, 6]]
        let triangles = quads.flatMap { [$0[0], $0[1], $0[2], $0[0], $0[2], $0[3]] }
        var mesh = TriangleMesh(positions: positions, normals: normals, triangles: triangles)
        mesh.creaseAngle = creaseAngle
        return mesh
    }

    /// A UV sphere of radius 5 with poles, `segments` around and `segments / 2` rings.
    static func sphere(segments: Int, creaseAngle: Double?) -> TriangleMesh {
        let rings = segments / 2
        var positions: [SIMD3<Float>] = [SIMD3(0, 0, 5)]
        for ring in 1..<rings {
            let polar = Double.pi * Double(ring) / Double(rings)
            for step in 0..<segments {
                let azimuth = 2 * Double.pi * Double(step) / Double(segments)
                positions.append(SIMD3(Float(5 * sin(polar) * cos(azimuth)), Float(5 * sin(polar) * sin(azimuth)), Float(5 * cos(polar))))
            }
        }
        positions.append(SIMD3(0, 0, -5))
        let south = UInt32(positions.count - 1)
        func at(_ ring: Int, _ step: Int) -> UInt32 { UInt32(1 + (ring - 1) * segments + step % segments) }
        var triangles: [UInt32] = []
        for step in 0..<segments { triangles += [0, at(1, step), at(1, step + 1)] }
        for ring in 1..<(rings - 1) {
            for step in 0..<segments {
                let (a, b, c, d) = (at(ring, step), at(ring + 1, step), at(ring + 1, step + 1), at(ring, step + 1))
                triangles += [a, b, c, a, c, d]
            }
        }
        for step in 0..<segments { triangles += [south, at(rings - 1, step + 1), at(rings - 1, step)] }
        var mesh = TriangleMesh(positions: positions, triangles: triangles)
        mesh.creaseAngle = creaseAngle
        return mesh
    }

    /// Two triangles hinged on the edge from (0,0,0) to (1,0,0), the second turned `degrees` out of the first's plane.
    static func hinge(degrees: Double, creaseAngle: Double?) -> TriangleMesh {
        let c = Float(cos(degrees * .pi / 180)), s = Float(sin(degrees * .pi / 180))
        var mesh = TriangleMesh(positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0), SIMD3(0.5, -c, s)],
                                triangles: [0, 1, 2, 1, 0, 3])
        mesh.creaseAngle = creaseAngle
        return mesh
    }

    func faceNormal(_ mesh: DisplayMesh, _ triangle: Int) -> Vector3 {
        let p = (0..<3).map { mesh.positions[Int(mesh.indices[3 * triangle + $0])] }
        return (p[1] - p[0]).cross(p[2] - p[0]).normalized ?? .zero
    }

    @Test func aWeldedBoxHasSixFlatNormals() {
        let display = Self.box(creaseAngle: 30).displayMesh
        #expect(display.positions.count == 24 && display.normals.count == 24)
        for triangle in 0..<12 {
            let flat = faceNormal(display, triangle)
            for corner in 0..<3 {
                let normal = display.normals[Int(display.indices[3 * triangle + corner])]
                #expect(normal.dot(flat) > 0.999_999, "triangle \(triangle) corner \(corner): \(normal) against \(flat)")
            }
        }
    }

    @Test func aSphereStaysSmooth() {
        let mesh = Self.sphere(segments: 64, creaseAngle: 30)
        let display = mesh.displayMesh
        #expect(display.positions.count == mesh.vertexCount)
        #expect(display.indices == mesh.triangles)
    }

    @Test func aThirtyOneDegreeEdgeSplitsAndATwentyNineDoesNot() {
        #expect(Self.hinge(degrees: 31, creaseAngle: 30).displayMesh.positions.count == 6)
        #expect(Self.hinge(degrees: 29, creaseAngle: 30).displayMesh.positions.count == 4)
    }

    @Test func theMeshNodesDisplayIsUnchanged() {
        // No crease angle: one display vertex per vertex, area-averaged normals, exactly as before.
        let smooth = Self.box(creaseAngle: nil).displayMesh
        #expect(smooth.positions.count == 8)
        let corner = smooth.normals[7]
        #expect(corner.dot(Vector3(1, 1, 1).normalized ?? .zero) > 0.999)
        // A mesh with normals of its own keeps them, crease angle or not.
        let given = [SIMD3<Float>](repeating: SIMD3(0, 0, 1), count: 8)
        let kept = Self.box(creaseAngle: 30, normals: given).displayMesh
        #expect(kept.positions.count == 8)
        #expect(kept.normals.allSatisfy { $0 == Vector3(0, 0, 1) })
    }

    @Test func triangleOrderIsKept() {
        var mesh = Self.box(creaseAngle: 30)
        mesh.highlights = [MeshHighlight(triangles: [3, 9], label: "x")]
        let display = mesh.displayMesh
        #expect(display.indices.count == mesh.triangles.count)
        #expect(display.triangleFaces == mesh.displayFaces)
        for triangle in 0..<mesh.triangleCount {
            let original = mesh.corners(of: triangle)
            let made = (0..<3).map { display.positions[Int(display.indices[3 * triangle + $0])] }
            #expect(made[0] == original.0 && made[1] == original.1 && made[2] == original.2)
        }
    }

    /// A hang is caught by the time limit; no wall-clock bound is asserted (benchmarks assert no time).
    @Test(.timeLimit(.minutes(5))) func aHugeFanStaysFast() {
        let rim = 200_000
        var positions: [SIMD3<Float>] = [.zero]
        for step in 0..<rim {
            let azimuth = 2 * Double.pi * Double(step) / Double(rim)
            positions.append(SIMD3(Float(10 * cos(azimuth)), Float(10 * sin(azimuth)), 0))
        }
        var triangles: [UInt32] = []
        for step in 0..<rim { triangles += [0, UInt32(1 + step), UInt32(1 + (step + 1) % rim)] }
        var mesh = TriangleMesh(positions: positions, triangles: triangles)
        mesh.creaseAngle = 30
        let display = mesh.displayMesh
        #expect(display.positions.count == rim + 1)
        #expect(display.normals.allSatisfy { $0.dot(Vector3(0, 0, 1)) > 0.999_999 })
    }

    @Test func aDegenerateFaceGivesFiniteNormals() {
        // A collinear triangle on the edge of a real one.
        var mesh = TriangleMesh(positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0), SIMD3(2, 0, 0)],
                                triangles: [0, 1, 2, 0, 1, 3, 0, 3, 3])
        mesh.creaseAngle = 30
        let display = mesh.displayMesh
        #expect(display.normals.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.z.isFinite && abs($0.length - 1) < 1e-9 })
        #expect(display.normals[Int(display.indices[0])].dot(Vector3(0, 0, 1)) > 0.999_999)
    }

    @Test func aFlippedNeighbourIsACrease() {
        // Both faces run 0 to 1: wound against the convention, so the edge is not joined even though the faces are coplanar.
        var mesh = TriangleMesh(positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0), SIMD3(0.5, -1, 0)],
                                triangles: [0, 1, 2, 0, 1, 3])
        mesh.creaseAngle = 30
        #expect(mesh.displayMesh.positions.count == 6)
    }

    @Test func anOpenEdgeIsACrease() {
        // Two coplanar triangles that were never welded: their edge is open on both sides and nothing joins them.
        let corners: [SIMD3<Float>] = [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0), SIMD3(1, 0, 0), SIMD3(0, 0, 0), SIMD3(0.5, -1, 0)]
        var mesh = TriangleMesh(positions: corners, triangles: [0, 1, 2, 3, 4, 5])
        mesh.creaseAngle = 30
        #expect(mesh.displayMesh.positions.count == 6)
        // Welded, the same pair is one smooth surface.
        var welded = TriangleMesh(positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0), SIMD3(0.5, -1, 0)],
                                  triangles: [0, 1, 2, 1, 0, 3])
        welded.creaseAngle = 30
        #expect(welded.displayMesh.positions.count == 4)
    }

    @Test func anOverfullEdgeIsACrease() {
        // Three coplanar faces on the edge 0-1: none is joined to another, so each corner there is its own vertex.
        var mesh = TriangleMesh(positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0.5, 1, 0), SIMD3(0.5, -1, 0), SIMD3(0.5, 2, 0)],
                                triangles: [0, 1, 2, 1, 0, 3, 0, 1, 4])
        mesh.creaseAngle = 30
        #expect(mesh.displayMesh.positions.count == 9)
    }

    @Test func exactlyThirtyDegreesIsNotACrease() {
        #expect(Self.hinge(degrees: 30, creaseAngle: 30).displayMesh.positions.count == 4)
    }

    @Test func aFlatSharedVertexKeepsItsOriginalIndexOrder() {
        // The first group of each vertex keeps the vertex's own index, so vertices that never split keep theirs.
        let display = Self.hinge(degrees: 90, creaseAngle: 30).displayMesh
        #expect(Array(display.positions.prefix(4)) == (0..<4).map { Self.hinge(degrees: 90, creaseAngle: 30).point($0) })
    }
}

#if canImport(Metal)
import Metal
@testable import CreatorViewport

/// An imported box under zebra stripes (Metal, offscreen): a mesh item is striped like any opaque solid, and with a crease angle each
/// face reflects one direction, so a face is one band; without it the corner-averaged normals bend and a face crosses several.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
struct MeshDisplayCreaseRenderTests {
    static let half = 7.0
    static let pose = CameraPose(target: .zero, distance: 20 / tan(CameraPose.fieldOfView / 2), yaw: 0.6, pitch: 0.5,
                                 projection: .orthographic)
    static let quads: [[Int]] = [[0, 4, 6, 2], [1, 3, 7, 5], [0, 1, 5, 4], [2, 6, 7, 3], [0, 2, 3, 1], [4, 5, 7, 6]]
    static let normals: [Vector3] = [
        Vector3(-1, 0, 0), Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(0, 0, 1),
    ]

    func render(_ mesh: TriangleMesh) throws -> [UInt8] {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try ViewportRenderer(device: device)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 400, height: 400, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        let target = try #require(device.makeTexture(descriptor: descriptor))
        let queue = try #require(device.makeCommandQueue())
        let box = BoundingBox(min: Vector3(-Self.half, -Self.half, -Self.half), max: Vector3(Self.half, Self.half, Self.half))
        var frame = ViewportFrame(pose: Self.pose, size: ViewportSize(width: 200, height: 200), sceneBounds: box,
                                  items: [
                                      FrameItem(meshSerial: 1, mesh: mesh.displayMesh, solidIndex: 0, isGhost: false, hoveredFace: nil,
                                                selectedFaces: [], selectedEdges: []),
                                  ],
                                  shading: .shadedEdges, gridSpacing: 10, handles: [], cube: ViewCubeLayout(), hoveredCubeRegion: nil,
                                  triad: TriadLayout())
        frame.zebra = ViewportZebra(direction: .horizontal, stripes: 12, blackShare: 0.5)
        frame.showsViewCube = false
        let commandBuffer = try #require(queue.makeCommandBuffer())
        renderer.encode(frame, into: target, scale: 2, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: 400 * 400 * 4)
        target.getBytes(&bytes, bytesPerRow: 400 * 4, from: MTLRegionMake2D(0, 0, 400, 400), mipmapLevel: 0)
        return bytes
    }

    /// How far the brightest and darkest of 41 samples along a line across each visible face are apart, per visible face.
    func spreads(_ bytes: [UInt8]) -> [Int] {
        var spreads: [Int] = []
        for (face, quad) in Self.quads.enumerated() where Self.normals[face].dot(Self.pose.toEye) > 0.3 {
            let corners = (0..<8).map { Vector3(($0 & 1) == 0 ? -Self.half : Self.half, ($0 & 2) == 0 ? -Self.half : Self.half,
                                                ($0 & 4) == 0 ? -Self.half : Self.half) }
            // A line across the face on one side of the triangles' shared diagonal, where the rasterizer leaves no seam.
            let (a, b, d) = (corners[quad[0]], corners[quad[1]], corners[quad[3]])
            var low = 255, high = 0
            for step in 0...40 {
                let point = a + (b - a) * 0.15 + (d - a) * (0.35 + 0.6 * Double(step) / 40)
                let x = Int((100 + 5 * point.dot(Self.pose.right)).rounded()), y = Int((100 - 5 * point.dot(Self.pose.up)).rounded())
                let value = Int(bytes[(y * 2 * 400 + x * 2) * 4])
                low = min(low, value)
                high = max(high, value)
            }
            spreads.append(high - low)
        }
        return spreads
    }

    @Test func aZebraRenderOfAnImportedBoxHasFlatFaces() throws {
        let flat = spreads(try render(MeshDisplayCreaseTests.box(creaseAngle: 30, half: Float(Self.half))))
        #expect(flat.count == 3)
        #expect(flat.allSatisfy { $0 < 20 }, "a face crosses bands: \(flat)")
        let smooth = spreads(try render(MeshDisplayCreaseTests.box(creaseAngle: nil, half: Float(Self.half))))
        #expect(smooth.contains { $0 > 100 }, "without a crease angle the faces should bend: \(smooth)")
    }
}
#endif
