import CreatorGraph
import CreatorKernel
import Foundation

extension AppModel {
    /// The name an export is offered under: the first Output node's name (spec §7.1, the Output node's name is the
    /// export name), else the document's.
    public var exportName: String {
        outputNodes.first.flatMap { document.graph.nodes[$0]?.name }
            ?? fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
    }

    /// The solids of every Output node, in ID order. Refused, with what to fix, when there's no Output node, an
    /// Output node has no result (an error upstream, or still evaluating), or no solid is wired in. Never exports a
    /// stale (ghosted) result.
    public func exportSolids() throws(AppProblem) -> [Solid] {
        let outputs = outputNodes.compactMap { document.graph.nodes[$0] }
        guard !outputs.isEmpty else {
            throw AppProblem("Nothing to export", "Add an Output node and wire the part into it.")
        }
        var solids: [Solid] = []
        for output in outputs {
            let result = document.results[output.id]
            guard let result, result.state.isSuccess else {
                throw AppProblem("“\(output.name)” can't be exported", Self.reason(result?.state))
            }
            for case .solid(let solid) in result.outputs?["solid"]?.items ?? [] { solids.append(solid) }
        }
        guard !solids.isEmpty else {
            throw AppProblem("Nothing to export", "No solid is wired into an Output node.")
        }
        return solids
    }

    /// Writes every output solid to `url` as STEP or STL (spec §7.2 step 5), once the document has evaluated.
    public func export(_ format: ExportFormat, to url: URL) async throws(AppProblem) {
        editor.commitPendingEntry()
        await document.waitForEvaluation()
        let solids = try exportSolids()
        do {
            try await kernel.export(solids, format: format, to: url)
        } catch {
            throw AppProblem("The \(format.rawValue.uppercased()) file couldn't be written", Evaluator.message(for: error))
        }
    }

    /// Export STEP… or STL…: says what's wrong before asking where, then the save panel, then the file.
    public func exportDocument(_ format: ExportFormat, using picker: any FilePicker) async {
        editor.commitPendingEntry()
        await document.waitForEvaluation()
        do {
            _ = try exportSolids()
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
}
