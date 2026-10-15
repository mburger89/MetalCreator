// Test fixture file: one rung of the preview triangle cap benchmark and the rule that picks the cap (Errata D15).
import Foundation

/// What the sweep measured at one rung of the ladder.
struct PreviewSweepRung {
    /// The window's CPU and GPU time per orbit frame, p95, in milliseconds.
    struct Orbit {
        var cpuP95: Double
        var gpuP95: Double
    }

    var resolution: Double
    var triangles: Int
    /// The median of three first-pass meshes on the GPU mesher, in milliseconds.
    var gpuMeshMilliseconds: Double
    /// The median of three on the CPU mesher over the GPU's values, in milliseconds.
    var cpuMeshMilliseconds: Double
    var panelShown: Orbit
    var panelHidden: Orbit
    /// The footprint the mesh in the viewport added, in bytes.
    var addedFootprint: Int
}

/// The rule that turns the rungs into a cap (proposed; the cap is the largest rung that meets all four).
enum PreviewSweepRule {
    /// (a) The orbit's GPU p95, half a 60 fps frame: the rest is MetalUI's own pass.
    static let gpuP95Budget = 8.0
    /// (b) How much the window CPU p95 may exceed the smallest rung's, in milliseconds.
    static let cpuP95Slack = 1.0
    /// (c) The footprint the mesh may add, in bytes.
    static let footprintBudget = 1_000_000_000
    /// (d) The GPU meshing of the pass, in milliseconds.
    static let meshBudget = 1000.0

    /// Whether each part of the rule holds for a rung.
    struct Verdict: Equatable {
        var gpuFrame: Bool
        var cpuFrame: Bool
        var footprint: Bool
        var meshing: Bool

        var passes: Bool { gpuFrame && cpuFrame && footprint && meshing }
    }

    /// `rung` judged against `smallest`, the first rung of the ladder.
    static func verdict(of rung: PreviewSweepRung, smallest: PreviewSweepRung) -> Verdict {
        Verdict(
            gpuFrame: rung.panelShown.gpuP95 <= gpuP95Budget && rung.panelHidden.gpuP95 <= gpuP95Budget,
            cpuFrame: rung.panelShown.cpuP95 <= smallest.panelShown.cpuP95 + cpuP95Slack
                && rung.panelHidden.cpuP95 <= smallest.panelHidden.cpuP95 + cpuP95Slack,
            footprint: rung.addedFootprint <= footprintBudget,
            meshing: rung.gpuMeshMilliseconds <= meshBudget)
    }

    /// The largest rung (by triangles) that passes, or `nil` when none does. `rungs` are in ladder order, the smallest first.
    static func capCandidate(_ rungs: [PreviewSweepRung]) -> PreviewSweepRung? {
        guard let smallest = rungs.first else { return nil }
        return rungs.filter { verdict(of: $0, smallest: smallest).passes }.max { $0.triangles < $1.triangles }
    }
}
