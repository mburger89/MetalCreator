import CreatorGeometry
import CreatorKernel

public enum ViewLabel {
    /// "Front", plus " (1 : 2)" when the view's scale differs from the sheet's; upper case for ASME (plan R18).
    public static func text(for view: DrawingView, sheet: DrawingSheet, standard: DrawingStandard) -> String {
        var text = title(of: view.orientation)
        if let scale = view.scale, abs(scale.value - sheet.scale.value) > 1e-12 {
            text += " (\(scale.text(for: standard)))"
        }
        return standard == .asme ? text.uppercased() : text
    }

    private static func title(of orientation: ViewOrientation) -> String {
        switch orientation {
        case .standard(let named): return named.title
        case .custom(let frame):
            for named in StandardOrientation.allCases where matches(named.frame, frame) { return named.title }
            return "View"
        }
    }

    private static func matches(_ a: ProjectionFrame, _ b: ProjectionFrame) -> Bool {
        (a.direction - b.direction).length <= 1e-9 && (a.up - b.up).length <= 1e-9
    }
}
