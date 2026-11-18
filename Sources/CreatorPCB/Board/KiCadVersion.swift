/// Board file versions where the format changes (facts §5, §6, §9).
public enum KiCadVersion {
    /// A file with no `(version …)` is read as this one.
    public static let missing = 20_201_115
    /// The last version that writes arcs as centre, start point and angle.
    public static let lastLegacyArcs = 20_210_925
    /// The first version that writes a footprint as `(transform …)` with its children in the library frame.
    public static let footprintTransform = 20_260_616
    /// KiCad 5: the chaining tolerance was 0.005 mm up to and including this version.
    public static let kicad5 = 20_171_130
    /// KiCad 7: the first version with the 0.01 mm chaining tolerance.
    public static let kicad7 = 20_221_018
    /// The first version KiCad reads `|…|` data tokens in, so the first with stored files.
    public static let embeddedFiles = 20_240_706
}
