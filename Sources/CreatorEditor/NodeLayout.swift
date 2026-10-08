import CreatorGeometry
import CreatorGraph

/// Node geometry computed, not measured, so drawing, socket anchors and hit testing agree
/// (ported from MetalNodes' `NodeGeometry`). All values are canvas points at zoom 1.
public enum NodeLayout {
    public static let width = 168.0
    public static let headerHeight = 24.0
    public static let rowHeight = 20.0
    public static let bodyPadding = 6.0
    public static let socketRadius = 5.0
    /// How far from a socket's centre a press still grabs it, in screen points.
    public static let socketHitRadius = 9.0

    /// Rows in the body: one per input, then one per output.
    public static func rowCount(_ shape: NodeShape) -> Int { max(1, shape.inputs.count + shape.outputs.count) }

    public static func size(_ shape: NodeShape) -> Vector2 {
        Vector2(width, headerHeight + 2 * bodyPadding + Double(rowCount(shape)) * rowHeight)
    }

    /// The vertical centre of body row `row`, from the node's top.
    public static func rowCentre(_ row: Int) -> Double {
        headerHeight + bodyPadding + (Double(row) + 0.5) * rowHeight
    }

    /// A socket's centre relative to the node's drawn origin. Horizontal flow: inputs on the
    /// left edge beside their rows, outputs on the right edge. Vertical flow: inputs spread
    /// along the top edge, outputs along the bottom (spec §6.2).
    public static func socketOffset(_ socket: SocketName, isInput: Bool, in shape: NodeShape, flow: CanvasFlow) -> Vector2? {
        let sockets = isInput ? shape.inputs : shape.outputs
        guard let index = sockets.firstIndex(where: { $0.name == socket }) else { return nil }
        switch flow {
        case .horizontal:
            let row = isInput ? index : shape.inputs.count + index
            return Vector2(isInput ? 0 : width, rowCentre(row))
        case .vertical:
            let x = width * Double(index + 1) / Double(sockets.count + 1)
            return Vector2(x, isInput ? 0 : size(shape).y)
        }
    }
}
