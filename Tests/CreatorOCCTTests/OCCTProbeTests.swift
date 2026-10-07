import Foundation
import Testing
@testable import CreatorOCCT

/// True when `a` and `b` agree to a relative tolerance (absolute near zero).
func isClose(_ a: Double, _ b: Double, relative: Double = 1e-6) -> Bool {
    abs(a - b) <= relative * max(1, abs(a), abs(b))
}

// STEP writing goes through OCCT's process-global Interface_Static settings, so the
// suite runs serially.
@Suite(.serialized)
struct OCCTProbeTests {
    @Test func boxHasExpectedVolumeAndTopology() throws {
        let box = try OCCTShape.box(10, 20, 30)
        #expect(isClose(box.volume, 6000))
        #expect(box.faceCount == 6)
        #expect(box.edgeCount == 12)
    }

    @Test func degenerateBoxThrowsInsteadOfCrashing() {
        #expect(throws: OCCTError.self) { try OCCTShape.box(0, 20, 30) }
    }
}
