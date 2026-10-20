import CreatorViewport

extension ViewportItem {
    /// True when `other` draws the same thing: the very same solid, ghosted alike, a guide alike, with the same faces and edges
    /// selected and the same field tint (arrays sharing storage compare in no time). `AppModel` re-shows the scene only when an
    /// item differs, so a canvas pan, a settled camera or a panel resize doesn't restart the viewport's mesh load (M4 carry-over:
    /// nothing rebuilds at 60 Hz).
    func drawsTheSame(as other: ViewportItem) -> Bool {
        solid === other.solid && isGhost == other.isGhost && isGuide == other.isGuide && selectedFaces == other.selectedFaces
            && selectedEdges == other.selectedEdges && fieldValues == other.fieldValues && fieldRamp == other.fieldRamp
            && warningFaces == other.warningFaces
    }

    /// True when the two scenes draw the same items in the same order.
    static func sameScene(_ a: [ViewportItem], _ b: [ViewportItem]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { $0.drawsTheSame(as: $1) }
    }
}
