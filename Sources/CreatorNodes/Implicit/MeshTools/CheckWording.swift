import CreatorImplicit
import CreatorKernel
import Foundation

/// The words of the mesh checks' warnings (implicit spec §3.6), written in `Locale.messages`.
enum CheckWording {
    /// The label a check run on a coarse copy carries before the full stop (implicit spec §3.6, Errata D12).
    static let previewLabel = "approximate: preview resolution"

    /// "Walls thinner than 0.4 mm in 3 places (thinnest 0.21 mm)." (spec §3.6; one place is "1 place").
    static func thinWalls(minimum: Double, places: Int, thinnest: Double, label: String?) -> String {
        let count = places.formatted(.number.locale(.messages))
        let noun = places == 1 ? "place" : "places"
        return sentence("Walls thinner than \(minimum.millimetreText(locale: .messages)) mm in \(count) \(noun) "
            + "(thinnest \(thinnest.millimetreText(locale: .messages)) mm)", label: label)
    }

    /// "3 enclosed voids can't drain." (spec §3.6; one is "1 enclosed void can't drain.").
    static func voids(_ count: Int, label: String?) -> String {
        let number = count.formatted(.number.locale(.messages))
        return sentence(count == 1 ? "\(number) enclosed void can't drain" : "\(number) enclosed voids can't drain", label: label)
    }

    /// The warning of a part so large that the grid's cells are coarser than 0.5 mm: a drain hole of the default 2 mm is then smaller
    /// than the cells can see through, so the check may report a void that is drained. Empty for the usual cell
    /// (`OccupancyGrid.largestCell`).
    static func coarseGrid(cell: Double) -> [String] {
        guard cell > OccupancyGrid.largestCell else { return [] }
        let (edge, hole) = (cell.millimetreText(locale: .messages), (4 * cell).millimetreText(locale: .messages))
        return ["The part is large: the check's cells are \(edge) mm, so holes under \(hole) mm may not count as open."]
    }

    /// `text`, then the label in brackets when there is one, then the full stop.
    private static func sentence(_ text: String, label: String?) -> String {
        label.map { "\(text) (\($0))." } ?? "\(text)."
    }

    /// The label for a check of `mesh`: a preview mesh is coarse.
    static func label(for mesh: TriangleMesh) -> String? {
        mesh.quality == .preview ? previewLabel : nil
    }
}
