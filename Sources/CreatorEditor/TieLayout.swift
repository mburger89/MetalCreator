import CreatorGeometry
import CreatorGraph

/// Where a tie is drawn (cable ties spec 2026-10-26 §5.1), in display canvas points. It has a lane for each wire it holds:
/// the lanes sit `laneSpacing` apart across the flow, centred on the tie's position, and are ordered by where each wire's
/// input sits across the flow, then by endpoint, to cut down crossings after the fan-out. Its band is a rounded rectangle
/// `bandLength` along the flow, spanning every lane and reaching `bandOverhang` beyond the outer ones.
public struct TieLayout: Equatable, Sendable {
    public static let laneSpacing = 4.0
    public static let bandLength = 6.0
    public static let bandOverhang = 3.0

    public var id: TieID
    /// Each wire's lane point.
    public var lanes: [Endpoint: Vector2]
    public var band: CanvasRect

    /// `inputs` are the input anchors of the wires (display canvas points); a wire without one has no lane.
    public init(_ tie: CableTie, inputs: [Endpoint: Vector2], flow: CanvasFlow) {
        let across: (Vector2) -> Double = { flow == .horizontal ? $0.y : $0.x }
        var placed: [(wire: Endpoint, across: Double)] = []
        for wire in tie.wires {
            if let input = inputs[wire] { placed.append((wire, across(input))) }
        }
        placed.sort { $0.across != $1.across ? $0.across < $1.across : $0.wire < $1.wire }
        let ordered = placed.map(\.wire)
        let centre = flow.display(tie.position)
        let unit = flow == .horizontal ? Vector2(0, 1) : Vector2(1, 0)
        let along = flow == .horizontal ? Vector2(1, 0) : Vector2(0, 1)
        let first = -Double(max(ordered.count - 1, 0)) * Self.laneSpacing / 2
        var lanes: [Endpoint: Vector2] = [:]
        for (index, wire) in ordered.enumerated() {
            lanes[wire] = centre + unit * (first + Double(index) * Self.laneSpacing)
        }
        let spread = Double(max(ordered.count - 1, 0)) * Self.laneSpacing + 2 * Self.bandOverhang
        id = tie.id
        self.lanes = lanes
        band = CanvasRect(origin: centre + unit * (first - Self.bandOverhang) - along * (Self.bandLength / 2),
                          size: along * Self.bandLength + unit * spread)
    }
}
