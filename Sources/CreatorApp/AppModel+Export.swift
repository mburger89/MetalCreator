import CreatorGraph
import CreatorImplicit
import CreatorKernel
import Foundation

extension AppModel {
    /// The name an export is offered under: the first Output node's name (spec §7.1, the Output node's name is the
    /// export name), else the document's.
    public var exportName: String {
        outputNodes.first.flatMap { document.graph.nodes[$0]?.name }
            ?? fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    /// What the Output nodes hold now: the solids of every one, in ID order, and which hold meshes. Refused, with what to fix, when
    /// there's no Output node, an Output node has no result (an error upstream, or still evaluating), or nothing is wired in. Never
    /// exports a stale (ghosted) result.
    func exportPlan() throws(AppProblem) -> ExportPlan {
        let outputs = outputNodes.compactMap { document.graph.nodes[$0] }
        guard !outputs.isEmpty else {
            throw AppProblem("Nothing to export", "Add an Output node and wire the part into it.")
        }
        var plan = ExportPlan()
        for output in outputs {
            let result = document.results[output.id]
            guard let result, result.state.isSuccess else {
                throw AppProblem("“\(output.name)” can't be exported", Self.reason(result?.state))
            }
            for case .solid(let solid) in result.outputs?["solid"]?.items ?? [] { plan.solids.append(solid) }
            if result.outputs?["mesh"]?.items.isEmpty == false { plan.meshOutputs.append(output.name) }
        }
        guard !plan.solids.isEmpty || plan.hasMeshes else {
            throw AppProblem("Nothing to export", "No solid is wired into an Output node.")
        }
        return plan
    }

    /// The solids of every Output node, in ID order, refused as `exportPlan()` refuses and when no Output holds a solid.
    public func exportSolids() throws(AppProblem) -> [Solid] {
        let plan = try exportPlan()
        guard !plan.solids.isEmpty else { throw AppProblem("Nothing to export", "No solid is wired into an Output node.") }
        return plan.solids
    }

    /// STEP needs solids (implicit spec §5.3): an Output holding a mesh is refused, in the words the spec gives.
    static func requireSolids(for format: ExportFormat, _ plan: ExportPlan) throws(AppProblem) {
        guard format == .step, let name = plan.meshOutputs.first else { return }
        throw AppProblem("The part can't be exported as STEP",
                         "Output '\(name)' is a mesh; STEP needs solids. Export STL or 3MF, or convert it with Mesh to Solid.")
    }

    /// Writes every Output node's solids and meshes to `url` as STEP or STL (spec §7.2 step 5), once the document has evaluated. An
    /// Output that holds a mesh is evaluated again at export resolution, in a sheet with a progress bar and Cancel
    /// (`exportRun`), and the file is STL; a cancelled export leaves no file. Afterwards a summary lists the warnings of the
    /// nodes the export came from.
    public func export(_ format: ExportFormat, to url: URL) async throws(AppProblem) {
        editor.commitPendingEntry()
        await document.waitForEvaluation()
        let plan = try exportPlan()
        try Self.requireSolids(for: format, plan)
        if plan.hasMeshes {
            try await exportMeshes(to: url)
            return
        }
        do {
            try await kernel.export(plan.solids, format: format, to: url)
        } catch {
            throw AppProblem("The \(format.rawValue.uppercased()) file couldn't be written", Evaluator.message(for: error))
        }
        summarize(Self.warnings(in: document.results, graph: document.graph, outputs: outputNodes))
    }

    /// Export STEP… or STL…: says what's wrong before asking where, then the save panel, then the file.
    public func exportDocument(_ format: ExportFormat, using picker: any FilePicker) async {
        editor.commitPendingEntry()
        await document.waitForEvaluation()
        do {
            try Self.requireSolids(for: format, try exportPlan())
            guard let url = try await picker.chooseDestination([.exported(format)],
                                                               defaultName: "\(exportName).\(format.rawValue)") else { return }
            try await export(format, to: url)
        } catch {
            report(error, title: "The part couldn't be exported")
        }
    }

    /// Why an Output node has nothing to export, from its state.
    static func reason(_ state: NodeState?) -> String {
        switch state {
        case .error(let message)?: message
        case .idle(let reason?)?: reason
        case .evaluating?: "It is still being evaluated."
        default: "It has no result yet."
        }
    }

    // MARK: Meshes

    /// What an export run of the graph made.
    private struct Collected {
        var solids: [Solid] = []
        var meshes: [TriangleMesh] = []
        var warnings: [String] = []
    }

    /// The tolerance solids are tessellated at when they share an STL file with meshes, in millimetres.
    private static let stlTolerance = 0.01

    private func exportMeshes(to url: URL) async throws(AppProblem) {
        let run = ExportRun(title: "Exporting “\(exportName)”")
        exportRun = run
        defer { exportRun = nil }
        let work = Task { try await evaluateForExport(run) }
        run.onCancel = { work.cancel() }
        let collected: Collected
        do {
            collected = try await work.value
        } catch is CancellationError {
            return
        } catch let problem as AppProblem {
            throw problem
        } catch {
            throw AppProblem("The part couldn't be exported", Evaluator.message(for: error))
        }
        // A Cancel that arrived as the evaluation finished still leaves no file.
        if run.isCancelling || Task.isCancelled { return }
        do {
            var writer = STLWriter()
            for solid in collected.solids {
                let mesh = try await kernel.tessellate(solid, tolerance: Self.stlTolerance)
                writer.add(positions: mesh.positions, indices: mesh.indices)
                if run.isCancelling { return }
            }
            for mesh in collected.meshes { writer.add(mesh) }
            if run.isCancelling { return }
            try writer.data().write(to: url, options: .atomic)
        } catch {
            throw AppProblem("The STL file couldn't be written", Evaluator.message(for: error))
        }
        summarize(collected.warnings)
    }

    /// Evaluates the graph to the Output nodes at export quality on an evaluator of its own (the document's keeps its preview results),
    /// reporting meshing progress to `run`.
    private func evaluateForExport(_ run: ExportRun) async throws -> Collected {
        let evaluator = Evaluator(registry: document.registry, kernel: kernel, implicitEngine: implicitEngine)
        let progress = MeshProgress { fraction in Task { @MainActor in run.report(fraction) } }
        let outputs = outputNodes
        let report = try await evaluator.evaluate(document.graph, definitions: document.definitions, demand: Set(outputs),
                                                  images: document.imageResolver, meshQuality: .export, progress: progress)
        let graph = document.graph
        var collected = Collected()
        for id in outputs {
            guard let output = graph.nodes[id] else { continue }
            guard let result = report.results[id], result.state.isSuccess else {
                // The Output only says it is waiting; the node that failed upstream says why.
                let failed = graph.upstreamClosure(of: id).sorted().compactMap { node -> (Node, String)? in
                    guard let node = graph.nodes[node], case .error(let message)? = report.results[node.id]?.state else { return nil }
                    return (node, message)
                }.first
                throw AppProblem("“\(failed?.0.name ?? output.name)” can't be exported",
                                 failed?.1 ?? Self.reason(report.results[id]?.state))
            }
            for case .solid(let solid) in result.outputs?["solid"]?.items ?? [] { collected.solids.append(solid) }
            for case .mesh(let payload) in result.outputs?["mesh"]?.items ?? [] {
                if let mesh = payload as? TriangleMesh { collected.meshes.append(mesh) }
            }
        }
        collected.warnings = Self.warnings(in: report.results, graph: graph, outputs: outputs)
        return collected
    }

    // MARK: Warnings

    /// The warnings of the nodes the Output nodes come from, each as "Node name: message", in node order.
    static func warnings(in results: [NodeID: NodeResult], graph: Graph, outputs: [NodeID]) -> [String] {
        let nodes = outputs.reduce(into: Set<NodeID>()) { $0.formUnion(graph.upstreamClosure(of: $1)) }
        return nodes.sorted().flatMap { id -> [String] in
            guard let node = graph.nodes[id], case .warning(let message)? = results[id]?.state else { return [] }
            return message.split(separator: "\n").map { "\(node.name): \($0)" }
        }
    }

    /// "Exported with 2 warnings", listing them, once the file is written; nothing when there are none.
    func summarize(_ warnings: [String]) {
        guard !warnings.isEmpty else { return }
        let count = warnings.count.formatted(.number.locale(.messages))
        alert = .problem(AppProblem("Exported with \(count) \(warnings.count == 1 ? "warning" : "warnings")",
                                    warnings.joined(separator: "\n")))
    }
}
