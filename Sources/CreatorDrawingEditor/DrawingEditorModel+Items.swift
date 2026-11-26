import CreatorDrawing
import CreatorKernel

/// The drawing's items: materials, part numbers and their order (DR-5 R5, R16). Any edit first writes the whole current order into
/// `items`, so editing one item never renumbers another.
extension DrawingEditorModel {
    public func setItemMaterial(_ text: String, of part: NodeID) {
        setItem(part) { $0.material = text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    public func setItemPartNumber(_ text: String, of part: NodeID) {
        setItem(part) { $0.partNumber = text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Moves an item up (negative) or down by `offset` places; past either end nothing happens.
    public func moveItem(_ part: NodeID, by offset: Int) {
        let numbered = PartItems.numbered(document, names: pinningNames)
        guard offset != 0, let index = numbered.firstIndex(where: { $0.part == part }) else { return }
        let target = index + offset
        guard numbered.indices.contains(target) else { return }
        commit(DrawingStepName.moveItem) { document in
            var items = PartItems.pinningOrder(document, names: self.pinningNames)
            let moved = items.remove(at: index)
            items.insert(moved, at: target)
            document.items = items
        }
    }

    /// Notes the names of parts the host just saw (DR-5 R5); in memory, never an edit. A part keeps its name after its Output goes.
    public func rememberPartNames(_ names: [NodeID: String]) {
        for (part, name) in names where rememberedPartNames[part] != name { rememberedPartNames[part] = name }
    }

    /// What each part is called: the facts' names, else the remembered ones (the order the balloons show, DR-5 R5).
    var partNames: [NodeID: String] { pinningNames }

    private var pinningNames: [NodeID: String] {
        var names = PartItems.names(of: partFacts)
        for (part, name) in rememberedPartNames where names[part] == nil { names[part] = name }
        return names
    }

    private func setItem(_ part: NodeID, _ change: (inout PartItem) -> Void) {
        let numbers = PartItems.numbered(document, names: pinningNames)
        guard numbers.contains(where: { $0.part == part }) else { return }
        commit(DrawingStepName.changeItem) { document in
            var items = PartItems.pinningOrder(document, names: self.pinningNames)
            guard let index = items.firstIndex(where: { $0.part == part }) else { return }
            let before = items[index]
            change(&items[index])
            // A value that didn't change commits nothing, not even the pinned order.
            guard items[index] != before else { return }
            document.items = items
        }
    }
}
