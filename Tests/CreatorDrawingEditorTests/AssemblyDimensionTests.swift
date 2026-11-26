import CreatorGeometry
import CreatorKernel
import Testing

@testable import CreatorDrawing
@testable import CreatorDrawingEditor

/// Dimensions picked in an assembly view: each pick is wrapped with its part and inferred as in a single view (DR-5 R3 over DR-2).
@MainActor
@Suite("Assembly dimensions")
struct AssemblyDimensionTests {
    private func dimension(_ s: AssemblyScene) throws -> DrawingDimension {
        let one = try #require(s.annotations.first, "\(s.h.model.refusal ?? "no annotation")")
        guard case .dimension(let made) = one.kind else {
            Issue.record("not a dimension: \(one.kind)")
            throw CancellationError()
        }
        return made
    }

    @Test func aCylinderOutlineIsADiameterOnItsAxis() throws {
        let s = AssemblyScene.make(orientation: .front) { n in
            let x = 100.0 * Double(n), id = AssemblyScene.shift * n
            return [
                AssemblyScene.line(Vector2(x + 17, -20), Vector2(x + 17, 0), .face(FaceID(2 + id))),
                AssemblyScene.line(Vector2(x + 23, -20), Vector2(x + 23, 0), .face(FaceID(2 + id))),
            ]
        }
        s.h.model.press(.dimension)
        s.click(s.at(123, -10))
        #expect(s.h.model.picks.count == 1, "\(s.h.model.refusal ?? "")")
        s.click(s.at(135, -10))
        #expect(s.h.log.commits.map(\.name) == ["Add Dimension"], "\(s.h.model.refusal ?? "")")
        let made = try dimension(s)
        #expect(made.kind == .diameter)
        guard case .onPart(let part, .axis)? = made.anchors.first else {
            Issue.record("expected an onPart axis anchor: \(made.anchors)")
            return
        }
        #expect(part == s.second)
        let id = try #require(s.annotations.first?.id)
        #expect(s.h.model.picture?.annotationReports[id]?.status == .held)
    }

    @Test func centreToCentreAnchorsOnTheCentres() throws {
        let s = AssemblyScene.make { n in
            let x = 100.0 * Double(n), id = AssemblyScene.shift * n
            return [
                AssemblyScene.line(Vector2(x, 0), Vector2(x + 40, 0), .edge(EdgeID(102 + id))),
                ProjectedLine(
                    visibility: .visible, lineClass: .sharp,
                    curve: .arc(center: Vector2(x + 20, 10), radius: 3, start: 0, sweep: 2 * .pi), source: .edge(EdgeID(id))),
            ]
        }
        s.h.model.press(.dimension)
        s.click(s.at(23, 10))
        s.click(s.at(123, 10))
        #expect(s.h.model.picks.count == 2, "\(s.h.model.refusal ?? "")")
        s.click(s.at(70, 30))
        #expect(s.h.log.commits.map(\.name) == ["Add Dimension"], "\(s.h.model.refusal ?? "")")
        let made = try dimension(s)
        #expect(made.anchors.count == 2)
        for (anchor, part) in zip(made.anchors, [s.first, s.second]) {
            guard case .onPart(let found, .centre) = anchor else {
                Issue.record("expected an onPart centre anchor: \(anchor)")
                return
            }
            #expect(found == part)
        }
        let id = try #require(s.annotations.first?.id)
        #expect(s.h.model.picture?.annotationReports[id]?.status == .held)
    }
}
