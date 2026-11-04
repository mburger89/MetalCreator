#if canImport(Darwin)
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Darwin
import Foundation
import Testing
@testable import CreatorApp

/// Mesh import (docs/verification/performance.md, "Mesh import"): rows `mesh-import-1` to `-3` are a million-triangle binary STL,
/// ASCII STL and 3MF read to the first display (the node through an `AppModel`, to the display meshes the viewport is given: read,
/// weld, edge counts, placement, crease split; no GPU, no window); rows `-4` to `-6` are the limit, 10,000,000 triangles of binary STL
/// as a height field (about 5 million vertices) and as an all-distinct soup (30 million), and a 3MF of a million. Each prints
/// `BENCH` lines with the time and the process's peak resident size (`ru_maxrss`, which only grows, so run one row per process:
/// `scripts/bench.sh 'MeshImportBench/binary1M'`). Release, recorded, not gated.
@MainActor
@Suite(.serialized, .enabled(if: Bench.isRequested, "set METALCREATOR_BENCH=1 (scripts/bench.sh)"))
struct MeshImportBench {
    @Test func binary1M() async throws { try await run("mesh-import-1 binary STL, 1,000,000 triangles", .binary(Fixture.field(1_000_000))) }
    @Test func ascii1M() async throws { try await run("mesh-import-2 ASCII STL, 1,000,000 triangles", .ascii(Fixture.field(1_000_000))) }
    @Test func threeMF1M() async throws { try await run("mesh-import-3 3MF, 1,000,000 triangles", .threeMF(Fixture.field(1_000_000))) }
    @Test func binary10MField() async throws {
        try await run("mesh-import-4 binary STL height field, 10,000,000 triangles", .binary(Fixture.field(10_000_000)))
    }

    @Test func binary10MSoup() async throws {
        try await run("mesh-import-5 binary STL soup, 10,000,000 triangles", .binary(Fixture.soup(10_000_000)))
    }

    /// The reader and the edge counts alone on the same files, for the split of the time (`mesh-import-4c` and `-5c`).
    @Test func parts10MField() throws {
        try parts("mesh-import-4c height field, 10,000,000 triangles", .binary(Fixture.field(10_000_000)))
    }

    @Test func parts10MSoup() throws { try parts("mesh-import-5c soup, 10,000,000 triangles", .binary(Fixture.soup(10_000_000))) }

    /// A placement-only edit after the first display (the second settle): what a cached parse leaves to do.
    @Test func placementEdit1M() async throws { try await edit(1_000_000, row: "mesh-import-7") }
    @Test func placementEdit10M() async throws { try await edit(10_000_000, row: "mesh-import-8") }

    private func edit(_ triangles: Int, row: String) async throws {
        guard Bench.requireRelease() else { return }
        let file = try Fixture.write(.binary(Fixture.field(triangles)))
        defer { try? FileManager.default.removeItem(at: file) }
        let (app, node) = try await Self.app(opening: file)
        await app.settle()
        let clock = ContinuousClock()
        var times: [Double] = []
        for round in 1...5 {
            try app.editor.edit(.setInput(node.id, "units", .integer(round % 2 == 0 ? 2 : 3)), name: "Change Units")
            let start = clock.now
            await app.settle()
            times.append(Self.milliseconds(clock.now - start))
        }
        #expect(app.document.results[node.id]?.outputs != nil)
        print("BENCH \(row) units edit after the first read, \(triangles) triangles: median \(Self.fixed(times.sorted()[2])) ms (n 5)")
    }

    private func run(_ name: String, _ kind: Fixture.Kind) async throws {
        guard Bench.requireRelease() else { return }
        let file = try Fixture.write(kind)
        defer { try? FileManager.default.removeItem(at: file) }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.size] as? Int) ?? 0
        let before = Self.peakMegabytes()
        let (app, node) = try await Self.app(opening: file)
        let clock = ContinuousClock()
        let start = clock.now
        await app.settle()
        let elapsed = Self.milliseconds(clock.now - start)
        let state = app.document.results[node.id]?.state
        let shown = app.viewport.items.count
        print("BENCH \(name): \(Self.fixed(elapsed)) ms to the first display, peak \(Self.peakMegabytes()) MB "
              + "(\(before) MB before the read; "
              + "file \(bytes / 1_000_000) MB; state \(String(describing: state)); \(shown) viewport items)")
        #expect(shown > 0)
    }

    private func parts(_ name: String, _ kind: Fixture.Kind) throws {
        guard Bench.requireRelease() else { return }
        let file = try Fixture.write(kind)
        defer { try? FileManager.default.removeItem(at: file) }
        let clock = ContinuousClock()
        var start = clock.now
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        let read = try STLReader.read(data, isCancelled: { false })
        let readTime = Self.milliseconds(clock.now - start)
        start = clock.now
        let counts = EdgeCounts(read.mesh)
        let countsTime = Self.milliseconds(clock.now - start)
        print("BENCH \(name): read and weld \(Self.fixed(readTime)) ms, EdgeCounts \(Self.fixed(countsTime)) ms, "
              + "peak \(Self.peakMegabytes()) MB; "
              + "\(read.mesh.vertexCount) vertices, open \(counts.open)")
    }

    private static func app(opening file: URL) async throws -> (AppModel, Node) {
        var builder = GraphBuilder()
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let node = builder.add(ImportMeshNode.self, [NodeSetting.meshFile: .meshFile(reference)])
        var graph = builder.graph
        graph.nodes[node.id]?.isOutput = true
        return (AppModel(kernel: FakeKernel(), file: GraphFile(graph: graph)), node)
    }

    static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }

    static func fixed(_ value: Double) -> String { String(format: "%.1f", value) }

    /// The process's peak resident set size so far, in megabytes (`ru_maxrss` is bytes on macOS).
    static func peakMegabytes() -> Int {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Int(usage.ru_maxrss) / 1_000_000
    }
}
#endif
