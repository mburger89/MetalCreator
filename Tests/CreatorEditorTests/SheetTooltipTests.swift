import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorEditor

private final class EmptyStorage: SolidStorage {
    let estimatedBytes = 0
}

/// NS-1 Task 9: a socket carrying a solid value that holds a sheet says so.
struct SheetTooltipTests {
    private func solid(open: Bool) -> Solid {
        let face = FaceInfo(id: FaceID(0), kind: .plane, normal: nil, area: 1, centroid: .zero, tags: [], isOnOpenShell: open)
        let edge = EdgeInfo(id: EdgeID(0), kind: .line, direction: nil, length: 1, midpoint: .zero, convexity: .unknown,
                            faces: open ? [FaceID(0)] : [FaceID(0), FaceID(1)])
        return Solid(topology: Topology(faces: [face], edges: [edge]), bounds: BoundingBox(min: .zero, max: .zero),
                     storage: EmptyStorage())
    }

    @Test func oneSheetIsCounted() {
        #expect(Value.one(.solid(solid(open: true))).sheetSummary == "1 sheet")
    }

    @Test func solidsAndASheetAreCounted() {
        let value = Value.list([.solid(solid(open: false)), .solid(solid(open: false)), .solid(solid(open: true))])
        #expect(value.sheetSummary == "2 solids and 1 sheet")
    }

    @Test func closedSolidsAndOtherValuesHaveNoSummary() {
        #expect(Value.one(.solid(solid(open: false))).sheetSummary == nil)
        #expect(Value.one(.number(3)).sheetSummary == nil)
    }
}
