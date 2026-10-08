// Test fixture file: the graph harness and value helpers shared by the node tests.
import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing

/// Builds a graph from built-in nodes and runs it through the real `Evaluator`.
struct Harness {
    private(set) var nodes: [NodeID: Node] = [:]
    private(set) var links: [Link] = []
    var parameters: [GraphParameter] = []

    var graph: Graph { Graph(nodes: nodes, links: links, parameters: parameters) }

    @discardableResult
    mutating func add(_ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:],
                      output: Bool = false) -> Node {
        // Created as the app creates nodes: seeded settings, and `isOutput` for Output nodes.
        var node = BuiltInNodes.registry.makeNode(definition.typeID)
        node.inputValues.merge(values) { _, given in given }
        if output { node.isOutput = true }
        nodes[node.id] = node
        return node
    }

    /// Wires `from.output` into `to.input`, recording an issue if the editor would refuse the wire.
    mutating func wire(_ from: Node, _ output: SocketName, to: Node, _ input: SocketName,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        let source = Endpoint(node: from.id, socket: output), target = Endpoint(node: to.id, socket: input)
        if let problem = graph.connectionProblem(from: source, to: target, registry: BuiltInNodes.registry) {
            Issue.record("can't wire \(from.name).\(output) → \(to.name).\(input): \(problem)", sourceLocation: sourceLocation)
        }
        links.append(Link(from: source, to: target))
    }

    mutating func set(_ node: Node, _ socket: SocketName, _ value: ConstantValue?) {
        nodes[node.id]?.inputValues[socket] = value
    }

    func run(_ demand: [Node], kernel: any Kernel = FakeKernel()) async throws -> EvaluationReport {
        try await Evaluator(registry: BuiltInNodes.registry, kernel: kernel).evaluate(graph, demand: Set(demand.map(\.id)))
    }
}

extension EvaluationReport {
    func state(_ node: Node) -> NodeState? { results[node.id]?.state }
    func value(_ node: Node, _ socket: SocketName) -> Value? { results[node.id]?.outputs?[socket] }

    func error(_ node: Node) -> String? {
        if case .error(let message)? = state(node) { message } else { nil }
    }

    func warning(_ node: Node) -> String? {
        if case .warning(let message)? = state(node) { message } else { nil }
    }

    /// True for `.ok`: succeeded with no warning.
    func isOK(_ node: Node) -> Bool {
        if case .ok? = state(node) { true } else { false }
    }
}

extension Value {
    var isList: Bool { if case .list = self { true } else { false } }

    func typed<T>(_ extract: (Scalar) -> T?) -> [T]? {
        let values = items.compactMap(extract)
        return values.count == items.count ? values : nil
    }

    var numbers: [Double]? { typed { if case .number(let v) = $0 { v } else { nil } } }
    var integers: [Int]? { typed { if case .integer(let v) = $0 { v } else { nil } } }
    var bools: [Bool]? { typed { if case .bool(let v) = $0 { v } else { nil } } }
    var vectors: [Vector3]? { typed { if case .vector(let v) = $0 { v } else { nil } } }
    var planes: [Plane]? { typed { if case .plane(let v) = $0 { v } else { nil } } }
    var profiles: [Profile2D]? { typed { if case .profile(let v) = $0 { v } else { nil } } }
    var solids: [Solid]? { typed { if case .solid(let v) = $0 { v } else { nil } } }
    var edgeSets: [EdgeSet]? { typed { if case .edgeSet(let v) = $0 { v } else { nil } } }
}

func isClose(_ a: Double, _ b: Double, relative: Double = 1e-6) -> Bool {
    abs(a - b) <= relative * max(1, abs(a), abs(b))
}

func isClose(_ a: Vector3, _ b: Vector3, tolerance: Double = 1e-9) -> Bool { (a - b).length <= tolerance }
