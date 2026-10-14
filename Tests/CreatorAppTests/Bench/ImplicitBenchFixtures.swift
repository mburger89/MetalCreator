// Test fixture file: the graphs and numbers of the implicit benchmarks (implicit spec §6), checked in the default run.
import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// What `ImplicitBench` measures. Row i-1's "gyroid sheet filling a 100 mm cube" is a TPMS node (a gyroid sheet) filling an Implicit Box
/// of that size, meshed and sent to an Output. (7c-1 benchmarked a noise sheet of the same cost class until the lattice nodes existed.)
@MainActor
enum ImplicitBenchFixtures {
    struct Sheet {
        var graph: Graph
        /// The TPMS node: a thickness edit is a change to its `thickness` input.
        var thickness: Node
        var output: Node
    }

    /// One gyroid cell across the cube. A gyroid sheet's surface is 3.09 cell² per cell, so a cube of 100 mm cells has about 61,800 mm²
    /// of wall faces: 196,128 triangles measured at 1.0 mm, so about 19.6 million at 0.1 mm (an estimate), about 3 GB in memory against
    /// the 4 GB budget; if a run goes over, a cell of 50 mm is the fallback. (8 mm cells have about 150 million,
    /// which no in-memory mesh holds: row i-4's target needs a sparse sheet, and the streamed export of D12 belongs to 7c-3.)
    static let cellSize = 100.0
    /// The wall, in millimetres.
    static let thickness = 3.0

    /// A gyroid sheet through a cube of `side` millimetres, `cell` millimetres per gyroid cell and `wall` thick, meshed at
    /// `exportResolution` for export.
    static func sheet(side: Double = 100, cell: Double = cellSize, wall: Double = thickness, exportResolution: Double = 0.1) -> Sheet {
        var builder = GraphBuilder()
        let cube = builder.add(ImplicitBoxNode.self, ["size": .vector(Vector3(side, side, side))])
        let gyroid = builder.add(TPMSNode.self, ["cell size": .number(cell), "thickness": .number(wall)])
        let mesh = builder.add(MeshNode.self, ["export resolution": .number(exportResolution)])
        let output = builder.add(OutputNode.self)
        builder.wire(cube, "implicit", to: gyroid, "region")
        builder.wire(gyroid, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: output, "mesh")
        return Sheet(graph: builder.graph, thickness: gyroid, output: output)
    }

    /// The process's peak resident memory so far, in bytes (0 where the platform has no `getrusage`).
    static var peakMemory: Int {
        #if canImport(Darwin)
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Int(usage.ru_maxrss)  // bytes on macOS
        #elseif canImport(Glibc)
        var usage = rusage()
        getrusage(__rusage_who_t(RUSAGE_SELF.rawValue), &usage)
        return Int(usage.ru_maxrss) * 1024  // kilobytes on Linux
        #else
        return 0
        #endif
    }
}
