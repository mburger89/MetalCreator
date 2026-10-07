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

    /// Index of the first edge whose length is `length`.
    func edgeIndex(of shape: OCCTShape, length: Double) throws -> Int {
        try #require((1...shape.edgeCount).first { isClose(shape.edgeLength(at: $0), length) })
    }

    @Test func filletRemovesTheAnalyticVolume() throws {
        let box = try OCCTShape.box(10, 20, 30)
        let filleted = try box.filleting(edge: try edgeIndex(of: box, length: 30), radius: 2)
        // A radius-r fillet along a length-L edge removes r²(1 − π/4)·L. For r = 2 that's (4 − π)·L.
        #expect(isClose(filleted.volume, 6000 - (4 - Double.pi) * 30))
        #expect(filleted.faceCount == 7)
    }

    @Test func oversizedFilletThrowsWithAMessage() throws {
        let box = try OCCTShape.box(10, 20, 30)
        let error = #expect(throws: OCCTError.self) {
            try box.filleting(edge: try edgeIndex(of: box, length: 30), radius: 15)
        }
        #expect(error?.message.isEmpty == false)
    }

    @Test func filletOnMissingEdgeThrows() throws {
        let box = try OCCTShape.box(10, 20, 30)
        #expect(throws: OCCTError.self) { try box.filleting(edge: 99, radius: 1) }
    }

    @Test func writesAStepFile() throws {
        let url = URL.temporaryDirectory.appending(path: "probe-\(UUID().uuidString).step")
        defer { try? FileManager.default.removeItem(at: url) }
        let box = try OCCTShape.box(10, 20, 30)
        try box.filleting(edge: try edgeIndex(of: box, length: 30), radius: 2).writeSTEP(to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.hasPrefix("ISO-10303-21;"))
        #expect(text.contains("MANIFOLD_SOLID_BREP"))
    }

    @Test func writesAnStlFile() throws {
        let url = URL.temporaryDirectory.appending(path: "probe-\(UUID().uuidString).stl")
        defer { try? FileManager.default.removeItem(at: url) }
        try OCCTShape.box(10, 20, 30).writeSTL(to: url, deflection: 0.1)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.hasPrefix("solid"))
        #expect(text.components(separatedBy: "facet normal").count - 1 >= 12)
    }

    @Test func stepToAnUnwritablePathThrows() throws {
        let url = URL(filePath: "/nonexistent-directory/probe.step")
        #expect(throws: OCCTError.self) { try OCCTShape.box(1, 1, 1).writeSTEP(to: url) }
    }
}
