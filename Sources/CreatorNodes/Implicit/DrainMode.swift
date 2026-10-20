/// How Drain Holes chooses where to drill (implicit spec §3.6): at points the person gives, or at the lowest point of every enclosed void.
enum DrainMode: Int, CaseIterable {
    case atPoints
    case automatic

    static let options = ["At Points", "Automatic"]
}
