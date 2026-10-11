/// How a hole's mouth is finished (patterns spec §5).
enum HoleStyle: Int, CaseIterable, Sendable {
    case plain, counterbore, countersink

    static let names = ["Plain", "Counterbore", "Countersink"]
}
