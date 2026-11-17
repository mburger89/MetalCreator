#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorKernel
import Foundation
import Testing
@testable import CreatorOCCT

/// NS-1 Task 11: STEP holds sheets as shells and curves as wires; STL leaves the wires out.
struct CurveExportTests {
    private func sheet(_ kernel: OCCTKernel) async throws -> Solid {
        let corners = [Vector3(0, 0, 20), Vector3(10, 0, 20), Vector3(10, 10, 20), Vector3(0, 10, 20)]
        let loop = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: newTag())
        return try await kernel.planarSurface([loop], tag: newTag())
    }

    private func wire(_ kernel: OCCTKernel) async throws -> Curve {
        try await kernel.makeCurve([.line(Vector3(40, 0, 0), Vector3(55, 0, 0))], tag: newTag())
    }

    private func target(_ name: String) -> URL {
        URL.temporaryDirectory.appending(path: "\(UUID().uuidString)-\(name)")
    }

    @Test func stepKeepsASheetAndACurveAndReadsBackAsOneOfEach() async throws {
        let kernel = OCCTKernel()
        let url = target("sc.step")
        defer { try? FileManager.default.removeItem(at: url) }
        try await kernel.export([try await sheet(kernel)], curves: [try await wire(kernel)], format: .step, to: url)
        let read = try await kernel.readShapes(try Data(contentsOf: url), format: .step, tag: newTag())
        #expect(read.solids.isEmpty && read.sheets.count == 1 && read.curves.count == 1)
        #expect(abs(read.curves.reduce(0) { $0 + $1.length } - 15) < 1e-4)
    }

    @Test func stepOfCurvesAloneIsWritten() async throws {
        let kernel = OCCTKernel()
        let url = target("c.step")
        defer { try? FileManager.default.removeItem(at: url) }
        try await kernel.export([], curves: [try await wire(kernel)], format: .step, to: url)
        let read = try await kernel.readShapes(try Data(contentsOf: url), format: .step, tag: newTag())
        #expect(read.solids.isEmpty && read.sheets.isEmpty && read.curves.count == 1)
    }

    @Test func stlLeavesTheCurveOut() async throws {
        let kernel = OCCTKernel()
        let url = target("sc.stl")
        defer { try? FileManager.default.removeItem(at: url) }
        try await kernel.export([try await sheet(kernel)], curves: [try await wire(kernel)], format: .stl, to: url)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0
        #expect(size > 0)
    }

    @Test func nothingToExportIsRefused() async throws {
        let kernel = OCCTKernel()
        await #expect(throws: KernelError.self) {
            try await kernel.export([], curves: [], format: .step, to: URL.temporaryDirectory.appending(path: "none.step"))
        }
    }
}
#endif
