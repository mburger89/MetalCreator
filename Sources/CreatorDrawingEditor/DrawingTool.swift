/// The tools of the drawing toolbar: DR-1's view tools, then DR-2's annotation tools.
public enum DrawingTool: Hashable, Sendable, CaseIterable {
    case select
    case baseView
    case projectedView
    case assemblyView
    case section
    case detail
    case auxiliaryView
    case dimension
    case baselineDimension
    case chainDimension
    case ordinateDimension
    case chamferDimension
    case holeCallout
    case centreMark
    case centreLine
    case note
    case datum
    case featureControlFrame
    case surfaceFinish
    case balloon
    case partsList
    case revisionTable
}

extension DrawingTool {
    /// The tool's name on its button, or `nil` for Select, which has none (Esc returns to it).
    public var title: String? {
        switch self {
        case .select: nil
        case .baseView: "Base View"
        case .projectedView: "Projected View"
        case .assemblyView: "Assembly View"
        case .section: "Section"
        case .detail: "Detail"
        case .auxiliaryView: "Auxiliary"
        case .dimension: "Dimension"
        case .baselineDimension: "Baseline"
        case .chainDimension: "Chain"
        case .ordinateDimension: "Ordinate"
        case .chamferDimension: "Chamfer"
        case .holeCallout: "Hole Callout"
        case .centreMark: "Centre Mark"
        case .centreLine: "Centre Line"
        case .note: "Note"
        case .datum: "Datum"
        case .featureControlFrame: "Feature Control Frame"
        case .surfaceFinish: "Surface Finish"
        case .balloon: "Balloon"
        case .partsList: "Parts List"
        case .revisionTable: "Revision Table"
        }
    }

    /// The three symbol tools (DR-4 R15): a first click names the target, the next places the symbol.
    public var isSymbolTool: Bool {
        switch self {
        case .datum, .featureControlFrame, .surfaceFinish: true
        default: false
        }
    }

    /// Whether the tool picks things on a view's lines or places a note (plan R17).
    public var isAnnotationTool: Bool {
        switch self {
        case .select, .baseView, .projectedView, .assemblyView, .section, .detail, .auxiliaryView: false
        default: true
        }
    }
}
