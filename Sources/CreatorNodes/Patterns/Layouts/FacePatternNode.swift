import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// Placements filling a flat face (patterns spec §3): a grid of `spacingX` by `spacingY` laid out on the face (the plane
/// Plane from Face would give: through the face's centroid, x axis from `FacePlane`), every second row moved half a pitch
/// with `stagger` (hex-style), each placement facing out along the face's normal. Only positions on the face are kept, and at
/// least `margin` from every edge of it, the edges of its holes included. The face is a remembered `FacePick`, the same as
/// Plane from Face's, so it follows the model.
///
/// One branch per grid cell, in a branch per row: a placement is `{row;column;0}`, the row counted from the lowest row the face's
/// box reaches and the column from the lowest column it reaches (a stagger's half pitch included), and a cell that is clipped
/// (off the face, in a hole or inside the margin) is an empty branch. So a vent keeps its path while the margin, a hole or the
/// spacing of a hole changes, and the cells that stay keep their names; only a face that grows past its box renumbers.
/// A curved face refuses ("Face Pattern works on flat faces for now."). More than 2,000 placements refuses.
public enum FacePatternNode: NodeDefinition {
    public static let typeID = "creator.facePattern"
    public static let displayName = "Face Pattern"
    public static let category = NodeCategory.patterns
    public static let inputs = [
        SocketSpec("solid", .solid),
        SocketSpec("spacingX", .number, defaultValue: .number(10), unit: .millimetres, range: 0.5...200),
        SocketSpec("spacingY", .number, defaultValue: .number(10), unit: .millimetres, range: 0.5...200),
        SocketSpec("stagger", .bool, defaultValue: .bool(false)),
        SocketSpec("margin", .number, defaultValue: .number(3), unit: .millimetres, range: 0...50),
    ]
    public static let outputs = [SocketSpec("placements", .plane)]
    public static var singleValuesRefusal: String? { LayoutChecks.singleValues(displayName) }
    public static let inspector = [
        InspectorSection(title: "Grid", controls: [.slider("spacingX"), .slider("spacingY"), .toggle("stagger", label: "Stagger")]),
        InspectorSection(title: "Edge", controls: [.slider("margin")]),
    ]

    /// The most grid positions tried, so a typo ("spacing 0.01") gives a message instead of a hang.
    static let maximumCandidates = 200_000

    static let nothingPicked = "Pick a face for this pattern to fill."
    static let unreadablePick = "This pattern's picked face can't be read. Pick the face again."
    static let noMatch = "The picked face isn't on this solid any more. Pick it again."
    static let notFlat = "Face Pattern works on flat faces for now."
    static let unnamedPick = "The picked face has no stable name, so the pattern may move to a different face "
        + "when the model changes. Pick it again after the change."
    static let mergedPick = "The picked face was merged with a face from another part of the model that has since changed, "
        + "so it isn't clear which part was picked. The pattern fills the closest one; pick the face again to settle it."

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solid = try inputs.solid("solid")
        let (spacingX, spacingY) = (try inputs.number("spacingX"), try inputs.number("spacingY"))
        guard spacingX.isFinite, spacingX > 0 else { throw NodeError.invalidValue("“spacingX” must be greater than 0 mm.") }
        guard spacingY.isFinite, spacingY > 0 else { throw NodeError.invalidValue("“spacingY” must be greater than 0 mm.") }
        let margin = try LayoutChecks.number(try inputs.number("margin"), "margin")
        let stagger = try inputs.bool("stagger")
        let (face, warnings) = try pickedFace(of: solid, context: context)
        let frame = try Frame(of: face)
        let region = try FaceRegion.outline(of: face, in: solid.topology, origin: frame.origin, xAxis: frame.xAxis, yAxis: frame.yAxis)
        guard let box = region.bounds else { throw NodeError.invalidValue(FaceRegion.unreadable) }
        // Rows j and columns i of the lattice through the centroid, as far as the face's box reaches. Worked out as Doubles and
        // checked against the cap before any Int is made, so a tiny spacing gives the message instead of a trap.
        let shift = stagger ? spacingX / 2 : 0
        let (lowRow, highRow) = ((box.min.y / spacingY).rounded(.up), (box.max.y / spacingY).rounded(.down))
        // Every row counts its columns from this one (a staggered row starts up to `shift` further right, never further left).
        let lowColumn = ((box.min.x - shift) / spacingX).rounded(.up)
        let columnsPerRow = (box.max.x - box.min.x + shift) / spacingX + 1
        let rowCount = max(highRow - lowRow + 1, 0)
        let limit = 1e15  // far above anything the cap allows, far below where Int(_:) traps
        guard rowCount * columnsPerRow <= Double(maximumCandidates), abs(lowRow) < limit, abs(highRow) < limit,
              abs(lowColumn) < limit else {
            throw NodeError.invalidValue("Face Pattern would have to try more than \(maximumCandidates.display) positions: "
                + "raise the spacing.")
        }
        // A stride is empty when highRow < lowRow (a face between two lattice rows); a closed range would trap there.
        let rows = stride(from: Int(lowRow), through: Int(highRow), by: 1)
        let firstColumn = Int(lowColumn)
        var rowBranches: [DataTree] = []
        var total = 0
        for row in rows {
            try Task.checkCancellation()
            let offset = abs(row) % 2 == 1 ? shift : 0
            let lastColumn = Int(((box.max.x - offset) / spacingX).rounded(.down))
            var cells: [DataTree] = []
            var column = firstColumn
            while column <= lastColumn {
                let local = Vector2(Double(column) * spacingX + offset, Double(row) * spacingY)
                if region.allows(local, margin: margin) {
                    total += 1
                    try PatternLimit.check(total)
                    cells.append(.list([LayoutChecks.placement(frame.point(local), normal: frame.normal, xAxis: frame.xAxis)]))
                } else {
                    cells.append(.list([]))
                }
                column += 1
            }
            rowBranches.append(DataTree(depth: 2, branches: cells) ?? .empty(depth: 2))
        }
        let tree = DataTree(depth: 3, branches: rowBranches) ?? .empty(depth: 3)
        return NodeOutputs(trees: ["placements": tree], warnings: warnings)
    }

    /// The area placements may stand in, for the viewport (patterns spec §8): the edge of the picked face moved `margin` into it,
    /// as 3D closed polylines (the first point not repeated). Empty when the face can't be found or read, which the node itself
    /// says in words. Exact on straight edges; a guide at corners and arcs (`FaceRegion.insetOutline`).
    public static func clippedArea(of solid: Solid, pick: FacePick, margin: Double) -> [[Vector3]] {
        guard let face = solid.topology.resolution(of: pick).faces.first, let frame = try? Frame(of: face),
              let region = try? FaceRegion.outline(of: face, in: solid.topology, origin: frame.origin, xAxis: frame.xAxis,
                                                   yAxis: frame.yAxis) else { return [] }
        return region.insetOutline(margin: max(margin, 0)).map { loop in loop.map(frame.point) }
    }

    /// The flat face the `face` setting names on `solid`, and the warnings its pick earns (as Plane from Face's: an ambiguous
    /// pick, several matches, an unnamed face). A pick on a copy a pattern no longer has is not retried on the part around it.
    private static func pickedFace(of solid: Solid, context: EvalContext) throws -> (FaceInfo, [String]) {
        let pick: FacePick
        switch context.node.inputValues[NodeSetting.face] {
        case nil: throw NodeError.invalidValue(nothingPicked)
        case .facePick(let stored)?: pick = stored
        case .some: throw NodeError.invalidValue(unreadablePick)
        }
        if let gone = solid.topology.vanishedInstances(in: pick.tags).first {
            throw NodeError.invalidValue("Instance \(InstancePath.text(gone)) no longer exists, so the picked face isn't there any more. "
                + "Pick the face again.")
        }
        let resolution = solid.topology.resolution(of: pick)
        guard let face = resolution.faces.first else { throw NodeError.invalidValue(noMatch) }
        guard face.kind == .plane, face.normal?.normalized != nil else { throw NodeError.invalidValue(notFlat) }
        var warnings: [String] = []
        if resolution.isAmbiguous {
            warnings.append(mergedPick)
        } else if resolution.faces.count > 1 {
            warnings.append("The pick matches \(resolution.faces.count.display) faces; the pattern fills the first.")
        }
        if pick.touchesUnnamedFace { warnings.append(unnamedPick) }
        return (face, warnings)
    }

    /// The face's own coordinates: its centroid, outward normal and the axes Plane from Face would give.
    struct Frame {
        let origin: Vector3
        let normal: Vector3
        let xAxis: Vector3
        let yAxis: Vector3

        init(of face: FaceInfo) throws {
            guard face.kind == .plane, let normal = face.normal?.normalized else { throw NodeError.invalidValue(FacePatternNode.notFlat) }
            let plane = FacePlane.plane(origin: face.centroid, normal: normal)
            (origin, self.normal, xAxis, yAxis) = (face.centroid, normal, plane.xAxis, plane.yAxis)
        }

        func point(_ local: Vector2) -> Vector3 { origin + xAxis * local.x + yAxis * local.y }
    }
}
