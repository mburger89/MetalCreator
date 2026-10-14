// Test fixture file: the graphs and numbers of the implicit benchmarks (implicit spec §6), checked in the default run.
import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp

/// What `ImplicitBench` measures. Row i-1's "gyroid sheet" is a sheet of the same cost class until the lattice nodes exist (7c-2): the
/// band of a noise field between two levels (one isosurface cut from another), held to a cube: a thin curved sheet through a 100 mm cube,
/// where each point costs two noise evaluations and a gyroid's costs one trigonometric sum. 7c-2 swaps this for the TPMS node and keeps
/// the rows' ids and targets.
@MainActor
enum ImplicitBenchFixtures {
    struct Sheet {
        var graph: Graph
        /// The Series node that makes the two levels, outer then inner: its `step` is the sheet's thickness in noise units.
        var levels: Node
        var output: Node
    }

    /// The noise the sheet follows: features 50 mm across, one octave, so a 100 mm cube holds a sheet or two. (A gyroid of 8 mm cells
    /// has about 150 million triangles at 0.1 mm, more than any in-memory mesh holds in 4 GB: row i-4's target needs a sparse sheet, and
    /// 7c-2 must choose its cell size knowing that.)
    static let noiseScale = 50.0
    static let noiseOctaves = 1
    static let outerLevel = 0.55
    static let thickness = 0.1

    /// A sheet through a cube of `side` millimetres, its noise features `scale` across, meshed at `exportResolution` for export.
    static func sheet(side: Double = 100, scale: Double = noiseScale, exportResolution: Double = 0.1) -> Sheet {
        var builder = GraphBuilder()
        let noise = builder.add(NoiseFieldNode.self, ["seed": .integer(1), "scale": .number(scale), "octaves": .integer(noiseOctaves)])
        let cube = builder.add(ImplicitBoxNode.self, ["size": .vector(Vector3(side, side, side))])
        let levels = builder.add(SeriesNode.self, ["start": .number(outerLevel), "step": .number(-thickness), "count": .integer(2)])
        // The slope the noise declares, held a little above so each isosurface's lipschitz bound is 1.
        let slope = (FieldNoise.slopeBound(scale: scale, octaves: noiseOctaves) * 100).rounded(.up) / 100
        let iso = builder.add(IsosurfaceNode.self, ["max slope": .number(slope)])
        let band = builder.add(ImplicitSubtractNode.self)
        let mesh = builder.add(MeshNode.self, ["export resolution": .number(exportResolution)])
        let output = builder.add(OutputNode.self)
        builder.wire(noise, "field", to: iso, "field")
        builder.wire(cube, "implicit", to: iso, "bounds")
        // Two levels make a list of two isosurfaces; Subtract cuts the second (the lower level) from the first.
        builder.wire(levels, "values", to: iso, "level")
        builder.wire(iso, "implicit", to: band, "shapes")
        builder.wire(band, "implicit", to: mesh, "implicit")
        builder.wire(mesh, "mesh", to: output, "mesh")
        return Sheet(graph: builder.graph, levels: levels, output: output)
    }

    /// The process's peak resident memory so far, in bytes (0 where the platform has no `getrusage`).
    static var peakMemory: Int {
        #if canImport(Darwin)
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Int(usage.ru_maxrss)  // bytes on macOS
        #elseif canImport(Glibc)
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Int(usage.ru_maxrss) * 1024  // kilobytes on Linux
        #else
        return 0
        #endif
    }
}
