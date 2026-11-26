import CreatorKernel

/// Where one part of an assembly view lies in the view's compound (DR-5 R2): positions in the compound topology's `faces` array and
/// in the compound's curves list. A part whose solids were all drawn earlier holds empty ranges at the running count.
public struct PartSpan: Hashable, Sendable {
    public var output: NodeID
    public var faces: Range<Int>
    public var curves: Range<Int>

    public init(output: NodeID, faces: Range<Int>, curves: Range<Int>) {
        self.output = output
        self.faces = faces
        self.curves = curves
    }
}

/// One shown part's solids and curves, the input of `PartSpan.layout(_:)` (the solids already cut to their remainders for a section).
public struct PartSolids: Sendable {
    public var output: NodeID
    public var solids: [Solid]
    public var curves: [Curve]

    public init(output: NodeID, solids: [Solid], curves: [Curve]) {
        self.output = output
        self.solids = solids
        self.curves = curves
    }
}

/// What the parts make together: the compound's solids and curves and each part's span. A value of the moment, never `Hashable`.
public struct PartLayout: Sendable {
    public var solids: [Solid]
    public var curves: [Curve]
    public var spans: [PartSpan]
    /// `part` showed a solid that `other` (an earlier part) had already given, so it is drawn once.
    public var shared: [(part: NodeID, other: NodeID)]
}

extension PartSpan {
    /// The one span rule (R2), shared by the projector and the app's last-good refresh: solids deduplicated by identity in order,
    /// curves concatenated, spans from cumulative face and curve counts.
    public static func layout(_ parts: [PartSolids]) -> PartLayout {
        var solids: [Solid] = []
        var curves: [Curve] = []
        var spans: [PartSpan] = []
        var shared: [(part: NodeID, other: NodeID)] = []
        var owners: [ObjectIdentifier: NodeID] = [:]
        var faceCount = 0
        for part in parts {
            let firstFace = faceCount, firstCurve = curves.count
            var earlier: [NodeID] = []
            for solid in part.solids {
                let id = ObjectIdentifier(solid)
                if let owner = owners[id] {
                    if owner != part.output, !earlier.contains(owner) { earlier.append(owner) }
                    continue
                }
                owners[id] = part.output
                solids.append(solid)
                faceCount += solid.topology.faces.count
            }
            curves += part.curves
            spans.append(PartSpan(output: part.output, faces: firstFace..<faceCount, curves: firstCurve..<curves.count))
            shared += earlier.map { (part: part.output, other: $0) }
        }
        return PartLayout(solids: solids, curves: curves, spans: spans, shared: shared)
    }
}

extension Array where Element == PartSpan {
    /// The span holding the face at `position` of the compound's `faces`.
    public func span(containingFace position: Int) -> PartSpan? {
        first { $0.faces.contains(position) }
    }

    /// The span holding the curve at `index` of the compound's curves.
    public func span(containingCurve index: Int) -> PartSpan? {
        first { $0.curves.contains(index) }
    }
}
