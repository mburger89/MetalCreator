#if canImport(CreatorOCCT)
import CreatorDrawing
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorOCCT

/// DR-3 Task 4: section content over OpenCascade (R5's sheet rule, per-part hatch, R4's step lines).
struct SectionContentOCCTTests {
    let kernel = OCCTKernel()
    let output = NodeID()
    let source = NodeTag(node: NodeID(), item: 0)
    let top = ProjectionFrame(direction: Vector3(0, 0, -1), up: Vector3(0, 1, 0))

    func rectangle(_ width: Double, _ height: Double, x: Double = 0) -> Profile2D {
        Profile2D(plane: .xy, segments: [
            .line(Vector2(x, 0), Vector2(x + width, 0)), .line(Vector2(x + width, 0), Vector2(x + width, height)),
            .line(Vector2(x + width, height), Vector2(x, height)), .line(Vector2(x, height), Vector2(x, 0)),
        ])
    }

    func box(x: Double = 0) async throws -> Solid {
        try await kernel.extrude(rectangle(40, 20, x: x), distance: 10, mode: .oneSided, tag: source)
    }

    func sheet(x: Double) async throws -> Solid {
        let corners = [Vector3(x, 0, 0), Vector3(x, 20, 0), Vector3(x + 20, 20, 0), Vector3(x + 20, 0, 0)]
        let loop = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: source)
        return try await kernel.planarSurface([loop], tag: source)
    }

    func view(_ points: [(Double, Double)]) -> DrawingView {
        let cutter = SectionCutter(frame: top, points: points.map { Vector2($0.0, $0.1) }, viewing: Vector2(0, 1))
        return DrawingView(
            kind: .section, source: output, orientation: .custom(SectionFrame.frame(for: cutter)), center: .zero,
            derivation: .section(SectionLine(parent: ViewID(), cutter: cutter)), letter: "A")
    }

    func content(_ solids: [Solid], _ points: [(Double, Double)] = [(-5, 5), (65, 5)]) async -> ViewContent {
        let projector = DrawingProjector(cache: ProjectionCache(), kernel: kernel)
        let state = DrawingSourceContent(
            output: output, name: "Output", state: .ready(solids: solids, curves: [], meshCount: 0))
        return await projector.content(for: view(points), scale: 1, source: state, previous: nil)
    }

    @Test func aSheetIsCutButNotHatched() async throws {
        let result = await content([try await sheet(x: 0)])
        #expect(result.problem == nil, "\(result.problem ?? "")")
        #expect(result.hatch.isEmpty)
        #expect(result.warnings.isEmpty)
        #expect(result.projection?.lines.isEmpty == false)
    }

    @Test func aMixedValueHatchesOnlyItsSolid() async throws {
        let mixed = try await kernel.compound([try await box(), try await sheet(x: 50)], tag: source)
        #expect(mixed.hasOpenShell && mixed.holdsClosedSolid)
        let result = await content([mixed])
        #expect(result.problem == nil, "\(result.problem ?? "")")
        #expect(!result.hatch.isEmpty)
        for region in result.hatch {
            for loop in region.edges { for point in loop { #expect(point.x > -1e-6 && point.x < 40 + 1e-6, "\(point)") } }
        }
        let lines = try #require(result.projection).lines
        #expect(lines.contains { line in
            let box = line.curve.bounds
            return box.min.x > 49 && box.max.x < 71
        })
    }

    @Test func twoSolidsTwoAngles() async throws {
        let result = await content([try await box(), try await box(x: 100)], [(-5, 5), (145, 5)])
        #expect(result.problem == nil, "\(result.problem ?? "")")
        #expect(Set(result.hatch.map(\.part)) == [0, 1])
    }

    @Test func aSteppedSectionHasNoLineAtTheStep() async throws {
        let result = await content([try await box()], [(-5, 5), (20, 5), (20, 15), (45, 15)])
        #expect(result.problem == nil, "\(result.problem ?? "")")
        let lines = try #require(result.projection).lines
        #expect(!lines.isEmpty)
        for line in lines {
            let box = line.curve.bounds
            let alongStep = abs(box.min.x - 20) < 1e-6 && abs(box.max.x - 20) < 1e-6 && box.height > 1e-6
            #expect(!alongStep, "\(line)")
        }
    }
}
#endif
