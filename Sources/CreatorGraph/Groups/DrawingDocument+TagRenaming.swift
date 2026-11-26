import CreatorDrawing
import CreatorKernel

extension DrawingDocument {
    /// This document with every pick of every annotation's anchors and leader targets (`EdgePick` keys, `FacePick`
    /// tags, nested blend tags) renamed by `names`, as `ConstantValue.renamingTags` renames a node's picks, so a
    /// dimension stays attached to its edge across Group, Ungroup and Make Unique (plan R21).
    func renamingTags(_ names: [NodeID: NodeID]) -> DrawingDocument {
        guard !names.isEmpty else { return self }
        var renamed = self
        for index in renamed.sheets.indices {
            for annotation in renamed.sheets[index].annotations {
                let new = annotation.renamingTags(names)
                if new != annotation { renamed.sheets[index].setAnnotation(new) }
            }
        }
        return renamed
    }
}

extension DrawingAnnotation {
    func renamingTags(_ names: [NodeID: NodeID]) -> DrawingAnnotation {
        var renamed = self
        switch kind {
        case .dimension(var dimension):
            dimension.anchors = dimension.anchors.map { $0.renamingTags(names) }
            renamed.kind = .dimension(dimension)
        case .holeCallout(var callout):
            callout.anchor = callout.anchor.renamingTags(names)
            renamed.kind = .holeCallout(callout)
        case .note(var note):
            note.leaders = note.leaders.map { LeaderEnd(target: $0.target.renamingTags(names), hint: $0.hint) }
            renamed.kind = .note(note)
        case .centreMark(var mark):
            mark.anchor = mark.anchor.renamingTags(names)
            renamed.kind = .centreMark(mark)
        case .centreLine(var line):
            line.anchor = line.anchor.renamingTags(names)
            renamed.kind = .centreLine(line)
        }
        return renamed
    }
}

extension AnchorTarget {
    func renamingTags(_ names: [NodeID: NodeID]) -> AnchorTarget {
        switch self {
        case .edge(let pick): .edge(TagRenaming.renaming(pick, names))
        case .corner(let first, let second): .corner(TagRenaming.renaming(first, names), TagRenaming.renaming(second, names))
        case .centre(let pick): .centre(TagRenaming.renaming(pick, names))
        case .outline(let face, let side): .outline(TagRenaming.renaming(face, names), side: side)
        case .axis(let face): .axis(TagRenaming.renaming(face, names))
        case .point: self
        }
    }
}
