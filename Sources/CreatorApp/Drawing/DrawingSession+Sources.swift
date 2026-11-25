import CreatorDrawing
import CreatorGraph
import CreatorKernel

extension DrawingSession {
    /// What an Output node holds now, as a view's source (plan R20): its solids and curves when it has a result, the Output's
    /// failure (or the first failing node upstream of it) when it has none, "evaluating" while the result is being made.
    static func content(of id: NodeID, in document: DocumentModel) -> DrawingSourceContent {
        guard let node = document.graph.nodes[id], node.isOutput else {
            return DrawingSourceContent(output: id, name: "", state: .removed)
        }
        let name = node.name
        guard document.graph.links.contains(where: { $0.to.node == id }) else {
            return DrawingSourceContent(output: id, name: name, state: .ready(solids: [], curves: [], meshCount: 0))
        }
        guard let result = document.results[id] else {
            let state: DrawingSourceContent.State =
                document.isEvaluating ? .evaluating : .ready(solids: [], curves: [], meshCount: 0)
            return DrawingSourceContent(output: id, name: name, state: state)
        }
        switch result.state {
        case .ok, .warning:
            return DrawingSourceContent(output: id, name: name, state: held(by: result))
        case .evaluating:
            return DrawingSourceContent(output: id, name: name, state: .evaluating)
        case .error(let message):
            return DrawingSourceContent(output: id, name: name, state: .failed(message))
        case .idle(let reason):
            let cause = upstreamFailure(of: id, in: document)
            return DrawingSourceContent(
                output: id, name: name,
                state: cause.map { .failed($0) } ?? (reason.map { .failed($0) } ?? .evaluating))
        }
    }

    private static func held(by result: NodeResult) -> DrawingSourceContent.State {
        var solids: [Solid] = []
        var curves: [Curve] = []
        var meshes = 0
        for (_, value) in (result.outputs ?? [:]).sorted(by: { $0.key < $1.key }) {
            for scalar in value.items {
                switch scalar {
                case .solid(let solid): solids.append(solid)
                case .curve(let curve): curves.append(curve)
                case .mesh: meshes += 1
                default: continue
                }
            }
        }
        return .ready(solids: solids, curves: curves, meshCount: meshes)
    }

    /// The first failing node upstream of `id` (by ID order), named, with its message; `nil` when nothing upstream failed.
    private static func upstreamFailure(of id: NodeID, in document: DocumentModel) -> String? {
        var seen: Set<NodeID> = [id]
        var queue = [id]
        var failures: [(NodeID, String)] = []
        while let next = queue.popLast() {
            for link in document.graph.links where link.to.node == next && seen.insert(link.from.node).inserted {
                if case .error(let message)? = document.results[link.from.node]?.state {
                    failures.append((link.from.node, message))
                }
                queue.append(link.from.node)
            }
        }
        guard let first = failures.min(by: { $0.0 < $1.0 }) else { return nil }
        let name = document.graph.nodes[first.0]?.name ?? "A node"
        return "“\(name)”: \(first.1)"
    }
}
