/// Where the imported board's origin goes (KiCad import spec, Inputs): KiCad's page origin, the board's drill/place origin or the
/// middle of its outline.
enum BoardOrigin: Int, CaseIterable {
    case page, drillPlace, boardCentre

    static let options = ["Page", "Drill/Place", "Board centre"]
}
