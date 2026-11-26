import CreatorKernel

/// One numbered line of the drawing's item list (DR-5 R5).
public struct NumberedItem: Hashable, Sendable {
    public var part: NodeID
    public var number: Int
    public var material: String
    public var partNumber: String

    public init(part: NodeID, number: Int, material: String, partNumber: String) {
        self.part = part
        self.number = number
        self.material = material
        self.partNumber = partNumber
    }
}

extension [NumberedItem] {
    /// The item number of `part`, or nil when the drawing doesn't want it.
    public func number(of part: NodeID) -> Int? { first { $0.part == part }?.number }
}

/// Item numbers are computed from the document and the parts' names, never stored (DR-5 R5), so balloons and the parts list can't disagree.
public enum PartItems {
    /// Every Output any view of any sheet shows and every balloon's part, each once: sheets in tab order, each sheet's views in
    /// order with their outputs in order, then that sheet's balloons.
    public static func wanted(in document: DrawingDocument) -> [NodeID] {
        var seen: Set<NodeID> = []
        var result: [NodeID] = []
        func add(_ part: NodeID) {
            if seen.insert(part).inserted { result.append(part) }
        }
        for sheet in document.sheets {
            for view in sheet.views { view.outputs.forEach(add) }
            for annotation in sheet.annotations {
                guard case .balloon(let balloon) = annotation.kind, let id = annotation.view,
                    let view = sheet.views.first(where: { $0.id == id })
                else { continue }
                add(balloon.part(in: view))
            }
        }
        return result
    }

    /// The wanted parts that `items` lists, in `items` order, then the others by name (ties by `NodeID`), then those with no name
    /// at all by `NodeID`; numbered 1, 2, 3 with no gap. An entry of a part no longer wanted takes no number.
    public static func numbered(_ document: DrawingDocument, names: [NodeID: String]) -> [NumberedItem] {
        let wanted = wanted(in: document)
        let wantedSet = Set(wanted)
        var listed: Set<NodeID> = []
        var order: [(part: NodeID, material: String, partNumber: String)] = []
        for item in document.items where wantedSet.contains(item.part) && listed.insert(item.part).inserted {
            order.append((item.part, item.material, item.partNumber))
        }
        let rest = wanted.filter { !listed.contains($0) }
        let named = rest.filter { names[$0] != nil }.sorted { left, right in
            let (a, b) = (names[left] ?? "", names[right] ?? "")
            return a == b ? left < right : a < b
        }
        let unnamed = rest.filter { names[$0] == nil }.sorted()
        for part in named + unnamed { order.append((part, "", "")) }
        return order.enumerated().map {
            NumberedItem(part: $1.part, number: $0 + 1, material: $1.material, partNumber: $1.partNumber)
        }
    }

    /// The current numbered order written as `items`, each entry's material and part number kept; entries of parts that are no
    /// longer wanted stay after them (R5: any item edit pins the order first).
    public static func pinningOrder(_ document: DrawingDocument, names: [NodeID: String]) -> [PartItem] {
        let numbered = numbered(document, names: names)
        var result = numbered.map { PartItem(part: $0.part, material: $0.material, partNumber: $0.partNumber) }
        let taken = Set(numbered.map(\.part))
        var seen: Set<NodeID> = []
        for item in document.items where !taken.contains(item.part) && seen.insert(item.part).inserted { result.append(item) }
        return result
    }

    /// Every entry's name, a removed part's remembered one included; an entry whose name is "?" is left out, so it sorts last.
    public static func names(of facts: [NodeID: PartFacts]) -> [NodeID: String] {
        var result: [NodeID: String] = [:]
        for (part, fact) in facts where fact.name != "?" { result[part] = fact.name }
        return result
    }
}
