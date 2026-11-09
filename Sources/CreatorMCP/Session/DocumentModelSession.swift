import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

/// A session over a bare `DocumentModel`: what the tests and the protocol need. The app's session adds files, export and
/// the rules about when an edit may run (Task 8).
@MainActor public final class DocumentModelSession: DocumentSession {
    /// A node's drawn width in points (the editor's `NodeLayout.width`, which this portable module can't import) and the gap
    /// left between it and the next.
    private static let nodeWidth = 224.0
    private static let nodeGap = 40.0
    private static let unavailable = "That isn't available here."

    public let document: DocumentModel
    private let initialContent: GraphContent
    /// The serials of the undo steps this client made, so it never takes back or re-applies the person's.
    private var clientSteps: Set<UInt64> = []
    private var clientUndone: Set<UInt64> = []

    /// Hooks for a session that wraps this one (the app's): the rule about when an edit may run, and what to do around a step
    /// so the serial tracking stays here.
    public var refusal: (@MainActor () -> String?)?
    public var willPerform: (@MainActor () -> Void)?
    public var didChange: (@MainActor () -> Void)?

    public init(document: DocumentModel) {
        self.document = document
        initialContent = document.content
    }

    public var content: GraphContent { document.content }
    public var registry: NodeRegistry { document.registry }
    public var results: [NodeID: NodeResult] { document.results }
    public var units: DocumentUnits { document.units }
    public var displayName: String { "Untitled" }
    public var isEdited: Bool { document.content != initialContent }
    public var fileURL: URL? { nil }

    public func outputSummary(of node: NodeID, socket: SocketName) -> String? {
        guard let value = document.results[node]?.outputs?[socket] else { return nil }
        return value.fieldSummary(limit: 80) ?? value.implicitSummary(limit: 80) ?? ValueSummary.describe(value)
    }

    public func editRefusal() -> String? { refusal?() }

    public func perform(_ command: GraphCommand, name: String) throws(GraphError) {
        willPerform?()
        defer { didChange?() }
        try document.perform(command, coalescingKey: nil, name: name)
        document.endCoalescing()
        if let top = document.topUndoEntry { clientSteps.insert(top.serial) }
    }

    /// Runs `body`, which makes one undo step of its own (the app's file settings), and counts that step as this client's.
    public func performExternal<E: Error>(_ body: () throws(E) -> Void) throws(E) {
        willPerform?()
        defer { didChange?() }
        let before = document.topUndoEntry?.serial
        try body()
        document.endCoalescing()
        if let top = document.topUndoEntry, top.serial != before { clientSteps.insert(top.serial) }
    }

    public func freePosition(for node: Node, in graph: Graph) -> Vector2 {
        let nodes = graph.nodes.values
        guard let rightmost = nodes.map(\.position.x).max(), let top = nodes.map(\.position.y).min() else { return .zero }
        return Vector2(rightmost + Self.nodeWidth + Self.nodeGap, top)
    }

    public func settle(within limit: Duration) async -> Bool {
        let gate = SettleGate()
        let document = document
        let waiter = Task { @MainActor in
            await document.waitForEvaluation()
            gate.finish(true)
        }
        let timer = Task { @MainActor in
            try? await Task.sleep(for: limit)
            gate.finish(false)
        }
        let settled = await gate.outcome()
        waiter.cancel()
        timer.cancel()
        return settled
    }

    public func undoClientStep() -> SessionOutcome {
        if let refusal = editRefusal() { return .refused(refusal) }
        willPerform?()
        guard let top = document.topUndoEntry, let name = document.undoName else { return .refused("There's nothing to undo.") }
        guard clientSteps.contains(top.serial) else { return .refused("The last step is yours, not mine: Undo \(name).") }
        document.undo()
        didChange?()
        clientUndone.insert(top.serial)
        return .done(name)
    }

    public func redoClientStep() -> SessionOutcome {
        if let refusal = editRefusal() { return .refused(refusal) }
        willPerform?()
        guard let top = document.topRedoEntry, let name = document.redoName else { return .refused("There's nothing to redo.") }
        guard clientUndone.contains(top.serial) else { return .refused("The next step to redo is yours: Redo \(name).") }
        document.redo()
        didChange?()
        clientUndone.remove(top.serial)
        return .done(name)
    }

    public func newDocument(discardUnsaved: Bool) -> SessionOutcome { .refused(Self.unavailable) }
    public func open(_ url: URL, discardUnsaved: Bool) -> SessionOutcome { .refused(Self.unavailable) }
    public func save(to url: URL?, overwrite: Bool) -> SessionOutcome { .refused(Self.unavailable) }

    public func export(_ kind: String, to url: URL, overwrite: Bool, progress: MCPCallContext) async -> SessionOutcome {
        .refused(Self.unavailable)
    }

    public func setFile(_ url: URL, on node: NodeID, embed: Bool) async -> SessionOutcome { .refused(Self.unavailable) }
}

/// A short description of a value's kind and count.
enum ValueSummary {
    static func describe(_ value: Value) -> String {
        let items = value.items
        let kinds = Set(items.map(\.type))
        guard let kind = kinds.first, kinds.count == 1 else { return "\(items.count) items" }
        let shape: String
        if case .one(let scalar) = value {
            return singular(scalar)
        } else if value.depth > 1 {
            shape = "tree of "
        } else {
            shape = ""
        }
        return "\(shape)\(items.count) \(plural(kind, count: items.count))"
    }

    private static func singular(_ scalar: Scalar) -> String {
        switch scalar {
        case .number(let number): "number \(format(number))"
        case .integer(let integer): "integer \(integer)"
        case .bool(let flag): "bool \(flag)"
        default: name(scalar.type)
        }
    }

    static func format(_ number: Double) -> String {
        guard number.isFinite else { return "\(number)" }
        let rounded = (number * 10_000).rounded() / 10_000
        return rounded == rounded.rounded() && abs(rounded) < 1e15 ? String(Int(rounded)) : "\(rounded)"
    }

    private static func name(_ type: SocketType) -> String {
        switch type {
        case .edgeSet: "edge set"
        case .faceSet: "face set"
        default: type.rawValue
        }
    }

    private static func plural(_ type: SocketType, count: Int) -> String {
        guard count != 1 else { return name(type) }
        return type == .mesh ? "meshes" : name(type) + "s"
    }
}

/// Whichever of the evaluation and the timer finishes first decides `settle`.
@MainActor private final class SettleGate {
    private var result: Bool?
    private var waiting: CheckedContinuation<Bool, Never>?

    func finish(_ value: Bool) {
        guard result == nil else { return }
        result = value
        waiting?.resume(returning: value)
        waiting = nil
    }

    func outcome() async -> Bool {
        if let result { return result }
        return await withCheckedContinuation { waiting = $0 }
    }
}
