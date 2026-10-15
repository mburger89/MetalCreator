// Test fixture file: the sheet, the resolution ladder and the memory reading of the preview triangle cap benchmark (Errata D15).
import CreatorGraph
import CreatorNodes
import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// What `PreviewSweepBench` meshes and how it reads memory. The sheet is `ImplicitBenchFixtures`' (a thin curved wall through a 100 mm
/// cube) with its noise features 8 mm across and a wall of about 1 mm: the gyroid's cell and wall until the TPMS node exists (7c-2), and
/// a surface with far more triangles per resolution than row i-1's 50 mm features have.
@MainActor
enum PreviewSweepFixtures {
    /// One step of the ladder: a voxel size, and the triangle count it was chosen to make (the run prints the real one).
    struct Rung: Equatable {
        var targetTriangles: Int
        var resolution: Double

        /// "0.25M" for a quarter of a million.
        var name: String {
            (Double(targetTriangles) / 1_000_000).formatted(.number.precision(.fractionLength(0...2)).locale(.messages)) + "M"
        }
    }

    /// Voxel sizes, in millimetres, that make about 0.25, 0.5, 1, 2, 4 and 8 million triangles of the default sheet. Measured on the GPU
    /// mesher (about 0.14M, 0.38M, 0.89M, 2.14M, 4.06M and 7.69M with the first values tried; triangles grow as the voxel size to
    /// the power of about -2); the run prints the counts it really made.
    static let ladder = [
        Rung(targetTriangles: 250_000, resolution: 1.9),
        Rung(targetTriangles: 500_000, resolution: 1.55),
        Rung(targetTriangles: 1_000_000, resolution: 1.22),
        Rung(targetTriangles: 2_000_000, resolution: 0.93),
        Rung(targetTriangles: 4_000_000, resolution: 0.65),
        Rung(targetTriangles: 8_000_000, resolution: 0.46),
    ]

    /// The cell of the pattern the sheet imitates, in millimetres.
    static let cell = 8.0
    /// The wall's thickness in noise units: about a millimetre across the sheet (measured; the noise's slope varies).
    static let wall = 0.2

    /// The sheet through a cube of `side` millimetres, its features `scale` across and its wall `thickness` in noise units.
    static func sheet(side: Double = 100, scale: Double = cell, thickness: Double = wall) -> ImplicitBenchFixtures.Sheet {
        var sheet = ImplicitBenchFixtures.sheet(side: side, scale: scale)
        sheet.graph.nodes[sheet.levels.id]?.inputValues["step"] = .number(-thickness)
        return sheet
    }

    /// `graph` with the Mesh node previewing at `resolution`: the first pass is at the larger of that and 128 cells across, and the
    /// refinement works down to it, so the mesh the viewport ends with is the rung's.
    static func previewing(_ graph: Graph, at resolution: Double) -> Graph {
        var graph = graph
        for (id, node) in graph.nodes where node.typeID == MeshNode.typeID {
            graph.nodes[id]?.inputValues["preview resolution"] = .number(resolution)
        }
        return graph
    }

    /// The process's physical footprint in bytes (`phys_footprint`, what Activity Monitor calls Memory), 0 where the platform has none.
    /// It counts compressed and GPU-mapped pages that the resident size leaves out.
    static var footprint: Int {
        #if canImport(Darwin)
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Int(info.phys_footprint) : 0
        #else
        return 0
        #endif
    }

    /// A footprint reading and how long it took to settle.
    struct Settled: Equatable {
        /// The footprint at the call, in bytes.
        var immediate: Int
        /// The footprint once it stopped falling, in bytes.
        var settled: Int
        var seconds: Double
        /// Bytes malloc has handed out and not had back (the live heap) when it settled.
        var heapInUse: Int
    }

    /// The footprint once freed memory has left the process. malloc keeps freed large blocks resident until a timer of about 10 s
    /// returns them (a dry run saw a rung's footprint fall from 1,444 MB to 1,025 MB 12 s after the rung, with nothing running and the
    /// live heap unchanged), so a reading taken at once includes the last rung's frees. This asks malloc to trim, then reads every
    /// `interval` until `stableReadings` readings in a row are within `tolerance` of each other (or `limit` seconds pass). The
    /// defaults settle what a mesh *adds* (the difference of two readings, which the timer moves alike); a reading of what is left
    /// behind needs `stableReadings` to span more than the timer.
    static func settledFootprint(interval: Duration = .milliseconds(500), stableReadings: Int = 3, tolerance: Double = 0.02,
                                 limit: Double = 30) async -> Settled {
        let immediate = footprint
        let clock = ContinuousClock()
        let start = clock.now
        var recent: [Int] = []
        while true {
            PreviewSweepRelease.returnFreedMemory()
            try? await Task.sleep(for: interval)
            recent.append(footprint)
            if recent.count > stableReadings { recent.removeFirst() }
            let seconds = (clock.now - start) / .seconds(1)
            if let high = recent.max(), let low = recent.min(), recent.count == stableReadings,
               Double(high - low) <= tolerance * Double(high) {
                return Settled(immediate: immediate, settled: recent.last ?? 0, seconds: seconds, heapInUse: PreviewSweepRelease.heapInUse)
            }
            if seconds >= limit {
                return Settled(immediate: immediate, settled: recent.last ?? 0, seconds: seconds, heapInUse: PreviewSweepRelease.heapInUse)
            }
        }
    }
}
