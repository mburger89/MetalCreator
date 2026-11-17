import CreatorGraph

/// Reads VRML text into `VRMLNode`s without knowing what any node means: a node is `Type {` fields and child nodes `}`, a field is
/// its name and a value (a list in brackets, a run of numbers, a word, a string or a node). Both VRML 1 and VRML 2 read this way; the
/// evaluator gives them their meaning. Nesting is limited to `maximumDepth` and the nodes to `maximumNodes`. The parser keeps its own
/// stack instead of recursing, so a hostile file's depth costs no more of the thread's stack than a plain one's.
final class VRMLParser {
    static let maximumDepth = 256
    static let maximumNodes = 2_000_000

    private enum Definition {
        case inProgress
        case done(VRMLNode)
    }

    /// Where a finished node goes in the frame below it.
    private enum Destination {
        case child
        case field(String)
        case listElement
    }

    private enum Frame {
        /// Fields and nodes until `}`; `name` is the node's `DEF` name.
        case body(VRMLNode, name: String?, destination: Destination)
        /// A bracketed list until `]`, the field of `owner` being read.
        case list(owner: VRMLNode, field: VRMLField)
    }

    private var tokenizer: VRMLTokenizer
    private let isCancelled: () -> Bool
    private var definitions: [String: Definition] = [:]
    private var nodeCount = 0
    private var stack: [Frame] = []
    /// How many nodes are open (the lists between them don't count).
    private var openNodes = 0

    init(_ bytes: UnsafeBufferPointer<UInt8>, isCancelled: @escaping () -> Bool) {
        tokenizer = VRMLTokenizer(bytes)
        self.isCancelled = isCancelled
    }

    /// The whole text as one pseudo node whose `children` are the top-level nodes.
    func parseFile() throws -> VRMLNode {
        let root = VRMLNode(type: "")
        stack = [.body(root, name: nil, destination: .child)]
        while !stack.isEmpty {
            guard let token = try next() else {
                guard stack.count == 1 else { throw VRMLReader.endsEarly }
                break
            }
            if case .list(let owner, _) = stack[stack.count - 1] {
                try step(inList: token, owner: owner)
            } else if case .body(let node, _, _) = stack[stack.count - 1] {
                try step(inBody: token, of: node)
            }
        }
        return root
    }

    private func next() throws -> VRMLTokenizer.Token? { try tokenizer.next(isCancelled: isCancelled) }

    private func peek() throws -> VRMLTokenizer.Token? { try tokenizer.peeked(isCancelled: isCancelled) }

    private func word() throws -> Range<Int> {
        guard case .word(let range)? = try next() else { throw VRMLReader.damaged }
        return range
    }

    private func peekIsOpenBrace() throws -> Bool { try peek() == .openBrace }

    private func startsNode(_ range: Range<Int>) throws -> Bool {
        if tokenizer.equals(range, "DEF") || tokenizer.equals(range, "USE") { return true }
        return try peekIsOpenBrace()
    }

    // MARK: Steps

    private func step(inBody token: VRMLTokenizer.Token, of node: VRMLNode) throws {
        switch token {
        case .closeBrace:
            guard stack.count > 1 else { throw VRMLReader.damaged }
            try finishBody()
        case .word(let range):
            if try startsNode(range) {
                try openNode(starting: range, destination: .child)
            } else if tokenizer.equals(range, "ROUTE") {
                for _ in 0..<3 { _ = try word() }
            } else if tokenizer.equals(range, "PROTO") || tokenizer.equals(range, "EXTERNPROTO") {
                try skipPrototype(external: tokenizer.equals(range, "EXTERNPROTO"))
            } else {
                try startField(named: tokenizer.text(range), of: node)
            }
        default:
            throw VRMLReader.damaged
        }
    }

    private func step(inList token: VRMLTokenizer.Token, owner: VRMLNode) throws {
        switch token {
        case .closeBracket:
            guard case .list(_, let field) = stack.removeLast() else { throw VRMLReader.damaged }
            owner.fields.append(field)
        case .string:
            return
        case .word(let range):
            if try startsNode(range) {
                try openNode(starting: range, destination: .listElement)
            } else if tokenizer.looksNumeric(range) {
                try updateList { $0.numbers.append(try tokenizer.number(range)) }
            } else {
                let text = tokenizer.text(range)
                try updateList { if $0.word == nil { $0.word = text } }
            }
        default:
            throw VRMLReader.damaged
        }
    }

    private func updateList(_ change: (inout VRMLField) throws -> Void) throws {
        guard case .list(let owner, var field) = stack.removeLast() else { throw VRMLReader.damaged }
        try change(&field)
        stack.append(.list(owner: owner, field: field))
    }

    /// The top body's closing brace: its node goes where its `destination` says, in the frame below.
    private func finishBody() throws {
        guard case .body(let node, let name, let destination) = stack.removeLast() else { throw VRMLReader.damaged }
        openNodes -= 1
        if let name { definitions[name] = .done(node) }
        try place(node, destination)
    }

    private func place(_ node: VRMLNode, _ destination: Destination) throws {
        switch (stack[stack.count - 1], destination) {
        case (.body(let parent, _, _), .child):
            parent.children.append(node)
        case (.body(let parent, _, _), .field(let name)):
            parent.fields.append(VRMLField(name: name, nodes: [node]))
        case (.list, .listElement):
            try updateList { $0.nodes.append(node) }
        default:
            throw VRMLReader.damaged
        }
    }

    /// A node whose first word (`DEF`, `USE` or the type) was just read: a `USE` is placed at once, any other opens a body frame.
    private func openNode(starting first: Range<Int>, destination: Destination) throws {
        if tokenizer.equals(first, "USE") {
            guard case .done(let node)? = definitions[tokenizer.text(try word())] else { throw VRMLReader.undefinedShape }
            try place(node, destination)
            return
        }
        var name: String?
        var typeRange = first
        if tokenizer.equals(first, "DEF") {
            let defined = tokenizer.text(try word())
            name = defined
            definitions[defined] = .inProgress
            typeRange = try word()
        }
        nodeCount += 1
        guard nodeCount <= Self.maximumNodes else { throw VRMLReader.tooComplex }
        guard openNodes < Self.maximumDepth else { throw VRMLReader.tooDeep }
        guard try next() == .openBrace else { throw VRMLReader.damaged }
        openNodes += 1
        stack.append(.body(VRMLNode(type: tokenizer.text(typeRange)), name: name, destination: destination))
    }

    /// The name of a field was read; its value is a list, a node, a run of numbers, a word or a string.
    private func startField(named name: String, of node: VRMLNode) throws {
        switch try next() {
        case .openBracket:
            stack.append(.list(owner: node, field: VRMLField(name: name)))
        case .word(let range)?:
            if try startsNode(range) {
                try openNode(starting: range, destination: .field(name))
            } else if tokenizer.looksNumeric(range) {
                var field = VRMLField(name: name, numbers: [try tokenizer.number(range)])
                while case .word(let more)? = try peek(), tokenizer.looksNumeric(more) {
                    _ = try next()
                    field.numbers.append(try tokenizer.number(more))
                }
                node.fields.append(field)
            } else {
                node.fields.append(VRMLField(name: name, word: tokenizer.text(range)))
            }
        case .string?:
            return
        default:
            throw VRMLReader.damaged
        }
    }

    // MARK: Prototypes

    /// `PROTO name [ interface ] { body }` and `EXTERNPROTO name [ interface ] "url"`: nothing here is evaluated, so both are skipped.
    private func skipPrototype(external: Bool) throws {
        _ = try word()
        guard try next() == .openBracket else { throw VRMLReader.damaged }
        try skipBalanced()
        if external {
            switch try next() {
            case .string: return
            case .openBracket: try skipBalanced()
            default: throw VRMLReader.damaged
            }
        } else {
            guard try next() == .openBrace else { throw VRMLReader.damaged }
            try skipBalanced()
        }
    }

    private func skipBalanced() throws {
        var depth = 1
        while let token = try next() {
            switch token {
            case .openBrace, .openBracket:
                depth += 1
                guard depth <= Self.maximumDepth else { throw VRMLReader.tooDeep }
            case .closeBrace, .closeBracket:
                depth -= 1
                if depth == 0 { return }
            default: break
            }
        }
        throw VRMLReader.endsEarly
    }
}
