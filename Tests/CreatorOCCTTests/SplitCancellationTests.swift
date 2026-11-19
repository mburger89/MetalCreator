#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-5 R15: the split shim stops on its cancel flag, in its own words.
struct SplitCancellationTests {
    let tag = NodeTag(node: NodeID(), item: 0)

    func sheetAndCutter(_ kernel: OCCTKernel) async throws -> (sheet: Solid, cutter: TrimCutter) {
        let corners = [Vector3(-10, -10, 0), Vector3(10, -10, 0), Vector3(10, 10, 0), Vector3(-10, 10, 0)]
        let outline = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: tag)
        let sheet = try await kernel.planarSurface([outline], tag: tag)
        let line = try await kernel.makeCurve([.line(Vector3(0, -20, 5), Vector3(0, 20, 5))], tag: tag)
        return (sheet, .curves([line], projection: .alongDirection, direction: .unitZ))
    }

    @Test func aCancelledSplitStopsInTheShimsWords() async throws {
        let kernel = OCCTKernel()
        let (sheet, cutter) = try await sheetAndCutter(kernel)
        let inputs = try await kernel.splitInputs(for: cutter)
        let source = try #require((sheet.storage as? OCCTSolidStorage)?.shape)
        let flag = OCCTCancelFlag()
        flag.cancel()
        #expect {
            try OCCTKernel.serialized {
                try OCCTShape.splitSheet(source, kind: inputs.kind, curves: inputs.wires, direction: inputs.direction,
                                         body: inputs.body, cancel: flag)
            }
        } throws: { ($0 as? OCCTError)?.message == OCCTCancelFlag.message }
        let task = Task { try await kernel.split(sheet, by: cutter, tag: tag) }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func anUncancelledSplitStillDivides() async throws {
        let kernel = OCCTKernel()
        let (sheet, cutter) = try await sheetAndCutter(kernel)
        let split = try await kernel.split(sheet, by: cutter, tag: tag)
        #expect(split.pieces.count == 2)
    }
}
#endif
