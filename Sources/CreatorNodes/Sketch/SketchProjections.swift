import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorSketch

/// Refreshes a sketch's projected edges before it is solved (sketcher spec §7, S1–S2 handoff). Each
/// projection's `EdgePick` is the node setting `NodeSetting.projection(reference)`. A pick that names
/// exactly one edge of the `references` solids gets that edge's projected curve; any other projection
/// is suspended (the solver skips its constraints and regions ignore it, nothing is deleted) and
/// named in a warning.
enum SketchProjections {
    enum Located {
        case found(EdgeInfo, drift: String?)
        case problem(String)
    }

    static let ignored = " Its constraints are ignored."

    /// Updates every projected entity of `sketch` in place and returns the warnings, in entity order.
    static func resolve(_ sketch: inout Sketch, settings: [SocketName: ConstantValue], references: [Solid],
                        on plane: Plane) -> [String] {
        var warnings: [String] = []
        for id in sketch.entityIDs {
            guard case .projected(var source)? = sketch.entities[id]?.kind else { continue }
            let label = sketch.label(of: id)
            var problem: String?
            switch locate(settings[NodeSetting.projection(source.reference)], in: references) {
            case .found(let edge, let drift):
                if let drift { warnings.append("\(label)'s pick changed. \(drift)") }
                switch EdgeProjection.project(edge, onto: plane) {
                case .curve(let curve): source.curve = curve
                case .refused(let reason): problem = "\(label) can't be projected: \(reason)."
                }
            case .problem(let text):
                problem = "\(label) \(text)"
            }
            source.isSuspended = problem != nil
            if let problem { warnings.append(problem + ignored) }
            sketch.entities[id]?.kind = .projected(source)
        }
        return warnings
    }

    /// The one edge a stored pick names among `references`, or why there isn't one. Each solid is
    /// matched by `EdgeTagMatch.choose` (tag subsets, then ordinals), the same as Edges by Tag (parent
    /// spec §5.3, narrowing a key that matches nothing), and a changed match count is reported in Edges by
    /// Tag's words, never silently (`EdgePick.hasDrifted(matching:inRuns:)`, as Edges by Tag).
    static func locate(_ setting: ConstantValue?, in references: [Solid]) -> Located {
        guard case .edgePicks(let picks)? = setting, picks.count == 1, let pick = picks.first else {
            return .problem("has no picked edge.")
        }
        guard !references.isEmpty else {
            return .problem("has no reference solid: wire the solid it was picked on into “references”.")
        }
        var found: [EdgeInfo] = []
        var matched = 0
        var runs = 0
        var isAmbiguous = false
        var vanished: Set<Int> = []
        for solid in references {
            // A pick on a placed copy that the pattern no longer has is not retried on the part around it (patterns spec §6).
            let gone = solid.topology.vanishedInstances(in: pick.key.first.union(pick.key.second))
            if !gone.isEmpty {
                vanished.formUnion(gone)
                continue
            }
            let choice = EdgeTagMatch.choose(pick, in: solid.topology, comparesRecordedCount: references.count == 1)
            matched += choice.matchCount
            runs += choice.runCount
            isAmbiguous = isAmbiguous || choice.isAmbiguous
            found += choice.chosen
        }
        switch found.count {
        case 0 where !vanished.isEmpty: return .problem(vanishedInstances(vanished.sorted()))
        case 0: return .problem("matches no edge of the references.")
        case 1:
            let drifted = pick.hasDrifted(matching: matched, inRuns: runs)
            let drift = drifted ? EdgeTagMatch.drift([(matched, pick.matchCount)]) : nil
            let guess = isAmbiguous ? EdgeTagMatch.ambiguousPick : nil
            let notes = [drift, guess].compactMap { $0 }
            return .found(found[0], drift: notes.isEmpty ? nil : notes.joined(separator: " "))
        default: return .problem("matches \(found.count.display) edges of the references.")
        }
    }

    /// "was picked on instance {4}, which no longer exists." (several paths are listed).
    static func vanishedInstances(_ items: [Int]) -> String {
        let paths = items.map(InstancePath.text).formatted(.list(type: .and).locale(.messages))
        return items.count == 1
            ? "was picked on instance \(paths), which no longer exists."
            : "was picked on instances \(paths), which no longer exist."
    }
}
