#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorOCCT

/// NS-5 Task 7: `Kernel.splitSolid(_:by:tag:)` (R13, R15).
struct SplitSolidTests {
    let kernel = OCCTKernel()
    let tag = newTag()

    /// The 10 mm box, z from 0 to 10, centred on the z axis.
    func tenBox() async throws -> Solid { try await box(kernel, 10, 10, 10) }

    /// A Planar Surface at `z`, `width` mm square about the z axis (normal +z), over `x` when given.
    func plane(z: Double, width: Double = 30, x: ClosedRange<Double>? = nil) async throws -> Solid {
        let xs = x ?? (-width / 2)...(width / 2)
        let y = width / 2
        let corners = [Vector3(xs.lowerBound, -y, z), Vector3(xs.lowerBound, y, z),
                       Vector3(xs.upperBound, y, z), Vector3(xs.upperBound, -y, z),
        ]
        let loop = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: newTag())
        return try await kernel.planarSurface([loop], tag: newTag())
    }

    /// A closed cylinder of radius 3 along z from -5 to 15.
    func cylinder() async throws -> Solid {
        try await kernel.extrude(.circle(radius: 3, center: .zero, plane: Plane.xy.offset(by: -5)), distance: 20, mode: .oneSided,
                                 tag: newTag())
    }

    func volume(_ solid: Solid) async throws -> Double { try await kernel.properties(of: solid).volume }

    func cutSides(_ solid: Solid, of name: CutterName? = nil) -> Set<CutSide> {
        var sides: Set<CutSide> = []
        for face in solid.topology.faces {
            for item in face.tags {
                if case .cutSide(let element, let side) = item.role, name == nil || element == name { sides.insert(side) }
            }
        }
        return sides
    }

    func sides(_ face: FaceInfo) -> [CutSide] {
        face.tags.compactMap { if case .cutSide(_, let side) = $0.role { side } else { nil } }
    }

    @Test func aPlaneCutsABoxInTwo() async throws {
        let part = try await tenBox()
        let cutter = try await plane(z: 5)
        let split = try await kernel.splitSolid(part, by: [cutter], tag: tag)
        #expect(split.pieces.count == 2 && split.warnings.isEmpty)
        let planeTags = cutter.topology.faces[0].tags
        for piece in split.pieces {
            #expect(!piece.hasOpenShell)
            #expect(try abs(await volume(piece) - 500) / 500 < 1e-6)
        }
        let lower = try #require(split.pieces.first { $0.bounds.max.z < 6 })
        let upper = try #require(split.pieces.first { $0.bounds.min.z > 4 })
        let lowerCut = try #require(lower.topology.faces.first { abs($0.centroid.z - 5) < 1e-6 })
        let upperCut = try #require(upper.topology.faces.first { abs($0.centroid.z - 5) < 1e-6 })
        #expect(planeTags.isSubset(of: lowerCut.tags) && planeTags.isSubset(of: upperCut.tags))
        #expect(lowerCut.tags.contains(TopoTag(tag, .cutSide(.face(planeTags), .back))))
        #expect(upperCut.tags.contains(TopoTag(tag, .cutSide(.face(planeTags), .front))))
        #expect(sides(lowerCut) == [.back] && sides(upperCut) == [.front])
        for (piece, side) in [(lower, CutSide.back), (upper, CutSide.front)] {
            let walls = piece.topology.faces.filter { abs($0.centroid.z - 5) > 1e-6 && abs($0.normal?.z ?? 1) < 1e-6 }
            #expect(walls.count == 4)
            #expect(walls.allSatisfy { sides($0) == [side] })
        }
    }

    @Test func aSolidToolCutsInsideAndOutside() async throws {
        let part = try await tenBox()
        let tool = try await cylinder()
        let split = try await kernel.splitSolid(part, by: [tool], tag: tag)
        #expect(split.pieces.count == 2)
        let core = Double.pi * 9 * 10
        let volumes = try await split.pieces.asyncMap { try await volume($0) }
        let inside = try #require(split.pieces.indices.first { abs(volumes[$0] - core) / core < 1e-6 })
        let outside = 1 - inside
        #expect(abs(volumes[outside] - (1000 - core)) / (1000 - core) < 1e-6)
        let lateral = { (piece: Solid) in piece.topology.faces.filter { $0.kind == .cylinder } }
        #expect(!lateral(split.pieces[inside]).isEmpty && lateral(split.pieces[inside]).allSatisfy { sides($0) == [.inside] })
        #expect(!lateral(split.pieces[outside]).isEmpty && lateral(split.pieces[outside]).allSatisfy { sides($0) == [.outside] })
        #expect(split.pieces.allSatisfy { !$0.hasOpenShell })
    }

    @Test func aDanglingToolWarnsAndLeavesNoInternalFace() async throws {
        let part = try await tenBox()
        let partial = try await plane(z: 3, width: 30, x: -15...0)
        let full = try await plane(z: 7)
        let split = try await kernel.splitSolid(part, by: [partial, full], tag: tag)
        #expect(split.pieces.count == 2)
        #expect(split.warnings == [OCCTKernel.danglingToolWarning])
        for piece in split.pieces {
            #expect(!piece.hasOpenShell)
            // No face lies inside the solid: the 6 faces of a box piece, and nothing of the partial plane.
            #expect(piece.topology.faces.count == 6)
            #expect(!piece.topology.faces.contains { abs($0.centroid.z - 3) < 1e-6 })
            let merged = try await kernel.boolean(.union, piece, [part], tag: newTag())
            #expect(!merged.topology.faces.isEmpty)
        }
    }

    @Test func aToolThatMissesIsRefused() async throws {
        let part = try await tenBox()
        let cutter = try await plane(z: 20)
        do {
            _ = try await kernel.splitSolid(part, by: [cutter], tag: tag)
            Issue.record("a plane outside the box divided it")
        } catch KernelError.invalidInput(let text) {
            #expect(text == "The tools don't cut the solid into pieces.")
        }
    }

    @Test func orderIsStable() async throws {
        let part = try await tenBox()
        let low = try await plane(z: 4)
        let high = try await plane(z: 6)
        let first = try await kernel.splitSolid(part, by: [low], tag: tag)
        let moved = try await kernel.splitSolid(part, by: [high], tag: tag)
        #expect(first.pieces.count == 2 && moved.pieces.count == 2)
        // The same half comes first whatever the plane's height.
        #expect((first.pieces[0].bounds.min.z < first.pieces[1].bounds.min.z)
            == (moved.pieces[0].bounds.min.z < moved.pieces[1].bounds.min.z))
        // Two tools in either order give the same three pieces in the same order.
        let both = try await kernel.splitSolid(part, by: [low, high], tag: tag)
        let reversed = try await kernel.splitSolid(part, by: [high, low], tag: tag)
        #expect(both.pieces.count == 3 && reversed.pieces.count == 3)
        #expect(zip(both.pieces, reversed.pieces).allSatisfy { abs($0.bounds.min.z - $1.bounds.min.z) < 1e-9 })
    }

    @Test func aCancelledSplitThrows() async throws {
        let part = try await tenBox()
        let cutter = try await plane(z: 5)
        let task = Task { try await kernel.splitSolid(part, by: [cutter], tag: tag) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        // The shim itself stops on the flag, in its own words (R15).
        let flag = OCCTCancelFlag()
        flag.cancel()
        let source = try #require((part.storage as? OCCTSolidStorage)?.shape)
        let tool = try #require((cutter.storage as? OCCTSolidStorage)?.shape)
        #expect {
            try OCCTKernel.serialized { try OCCTShape.splitSolid(source, tools: [tool], cancel: flag) }
        } throws: { ($0 as? OCCTError)?.message == OCCTCancelFlag.message }
    }

    @Test func aMixedToolNamesEachFaceByItsKind() async throws {
        let part = try await tenBox()
        let tool = try await kernel.compound([cylinder(), plane(z: 8)], tag: newTag())
        let split = try await kernel.splitSolid(part, by: [tool], tag: tag)
        #expect(split.pieces.count == 4)
        var total = 0.0
        for piece in split.pieces {
            #expect(!piece.hasOpenShell)
            total += try await volume(piece)
            for face in piece.topology.faces {
                for item in face.tags {
                    guard case .cutSide(let element, let side) = item.role, case .face(let tags) = element else { continue }
                    let fromPlane = tool.topology.faces.contains { $0.tags == tags && $0.kind == .plane }
                    let fromCylinder = tool.topology.faces.contains { $0.tags == tags && $0.kind == .cylinder }
                    if fromCylinder && !fromPlane { #expect(side == .inside || side == .outside) }
                    if fromPlane && !fromCylinder { #expect(side == .front || side == .back) }
                }
            }
        }
        #expect(abs(total - 1000) / 1000 < 1e-6)
        let all = split.pieces.reduce(into: Set<CutSide>()) { $0.formUnion(cutSides($1)) }
        #expect(all == [.front, .back, .inside, .outside])
    }
}

extension Sequence {
    fileprivate func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self { result.append(try await transform(element)) }
        return result
    }
}
#endif
