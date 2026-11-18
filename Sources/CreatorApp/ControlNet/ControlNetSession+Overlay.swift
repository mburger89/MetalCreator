import CreatorGeometry
import CreatorKernel
import CreatorViewport

extension ControlNetSession {
    /// The net's lines between neighbours in u and in v (dashed construction) and its points, over the model.
    var overlay: ViewportOverlay {
        var overlay = ViewportOverlay()
        for i in 0..<net.uCount {
            for j in 0..<net.vCount {
                guard let here = position(of: PoleIndex(i: i, j: j)) else { continue }
                if let next = position(of: PoleIndex(i: i + 1, j: j)) {
                    overlay.lines.append(OverlayLine(here, next, tint: .construction, width: 1, isDashed: true))
                }
                if let next = position(of: PoleIndex(i: i, j: j + 1)) {
                    overlay.lines.append(OverlayLine(here, next, tint: .construction, width: 1, isDashed: true))
                }
            }
        }
        for i in 0..<net.uCount {
            for j in 0..<net.vCount {
                let index = PoleIndex(i: i, j: j)
                guard let world = position(of: index) else { continue }
                let tint: OverlayTint = selection.contains(index) ? .selected : (hover == index ? .hovered : .underConstrained)
                overlay.points.append(OverlayPoint(world, tint: tint, size: 7))
            }
        }
        return overlay
    }
}
