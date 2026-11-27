import CreatorGeometry
import CreatorKernel

/// The sentences a derived view shows when its parent no longer fits its marks (DR-3 R6): sections and auxiliary views keep working
/// from their stored data, and say why the cutting line or arrow isn't drawn.
public enum DerivedViewNotices {
    public static let sectionParentDeleted = "The view this section was cut from was deleted, so its cutting line isn't shown."
    public static let sectionParentTurned = "The view this section was cut from now looks another way, so its cutting line isn't shown."
    public static let auxiliaryParentDeleted =
        "The view this auxiliary view was projected from was deleted, so its arrow isn't shown."
    public static let auxiliaryParentTurned =
        "The view this auxiliary view was projected from now looks another way, so its arrow isn't shown."

    public static let sectionParentEmpty =
        "The view this section was cut from has nothing drawn yet, so its cutting line isn't shown."
    public static let auxiliaryParentEmpty =
        "The view this auxiliary view was projected from has nothing drawn yet, so its arrow isn't shown."

    public static let detailParentEmpty = "The view this detail enlarged has nothing drawn yet, so its circle isn't shown."

    /// `contents` is what each view shows now: a parent with no projection has no mapping to draw the mark on.
    public static func notices(for view: DrawingView, in sheet: DrawingSheet, contents: [ViewID: ViewContent]) -> [String] {
        switch view.derivation {
        case .section(let line):
            return notice(
                parent: line.parent, stored: line.cutter.frame, in: sheet, contents: contents,
                sentences: (sectionParentDeleted, sectionParentTurned, sectionParentEmpty))
        case .auxiliary(let arrow):
            return notice(
                parent: arrow.parent, stored: arrow.parentFrame, in: sheet, contents: contents,
                sentences: (auxiliaryParentDeleted, auxiliaryParentTurned, auxiliaryParentEmpty))
        case .detail(let circle):
            // A deleted parent is the view's own problem sentence (`DetailClip.parentDeletedSentence`); one with nothing drawn has
            // no mapping to put the circle on.
            guard let parent = sheet.view(circle.parent), parent.id != view.id else { return [] }
            let content = contents[parent.id] ?? ViewContent()
            return (content.framing ?? content.projection?.bounds) == nil ? [detailParentEmpty] : []
        case nil:
            return []
        }
    }

    /// Whether a section's or auxiliary view's marks are drawn: its parent is on the sheet and looks as it did.
    public static func marksAreShown(for view: DrawingView, in sheet: DrawingSheet, contents: [ViewID: ViewContent]) -> Bool {
        switch view.derivation {
        case .section, .auxiliary: notices(for: view, in: sheet, contents: contents).isEmpty
        case .detail, nil: false
        }
    }

    private static func notice(
        parent: ViewID, stored: ProjectionFrame, in sheet: DrawingSheet, contents: [ViewID: ViewContent],
        sentences: (deleted: String, turned: String, empty: String)
    ) -> [String] {
        guard let parent = sheet.view(parent) else { return [sentences.deleted] }
        guard matches(parent.orientation.frame, stored) else { return [sentences.turned] }
        let content = contents[parent.id] ?? ViewContent()
        return (content.framing ?? content.projection?.bounds) == nil ? [sentences.empty] : []
    }

    private static func matches(_ a: ProjectionFrame, _ b: ProjectionFrame) -> Bool {
        (a.direction - b.direction).length <= 1e-9 && (a.up - b.up).length <= 1e-9
    }
}
