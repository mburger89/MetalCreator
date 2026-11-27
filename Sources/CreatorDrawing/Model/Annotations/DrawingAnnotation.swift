public enum AnnotationKind: Hashable, Sendable {
    case dimension(DrawingDimension)
    case holeCallout(HoleCallout)
    case centreMark(CentreMark)
    case centreLine(CentreLine)
    case note(DrawingNote)
    case datumFeature(DatumFeature)
    case featureControl(FeatureControlFrame)
    case surfaceTexture(SurfaceTexture)
    case balloon(Balloon)
    case partsList(PartsList)
    case revisionTable(RevisionTable)
}

/// One annotation of a sheet (plan R2): on a view (`view`), or free on the sheet when nil.
public struct DrawingAnnotation: Hashable, Codable, Sendable, Identifiable {
    public var id: AnnotationID
    public var view: ViewID?
    public var kind: AnnotationKind
    public var last: LastGood?

    public init(id: AnnotationID = AnnotationID(), view: ViewID?, kind: AnnotationKind, last: LastGood? = nil) {
        self.id = id
        self.view = view
        self.kind = kind
        self.last = last
    }
}

extension DrawingAnnotation {
    /// What a datum or frame stands on, the `feature` of a surface symbol, nil for any other kind (plan R1).
    public var symbolAttachment: SymbolAttachment? {
        switch kind {
        case .datumFeature(let datum): datum.attachment
        case .featureControl(let frame): frame.attachment
        case .surfaceTexture(let texture): .feature(texture.feature)
        default: nil
        }
    }

    /// The symbol kind, nil for any other annotation.
    public var symbolKind: SymbolKind? {
        switch kind {
        case .datumFeature: .datum
        case .featureControl: .frame
        case .surfaceTexture: .surface
        default: nil
        }
    }
}

extension DrawingAnnotation {
    /// The annotation with every placement field set to a fixed value (drawings speed R5): a field `AnnotationRefresh.lastGood`
    /// never reads, so two annotations that differ only in where they sit give the same figure and the app's refresh key
    /// (`RefreshKey.annotations`) holds this form. Per kind:
    ///
    /// - dimension: `placement.offset` (kept as its side, 5 or -5, because the side picks which end of a line is measured from),
    ///   `placement.textShift`; its `placement.angle` is read only by an angle dimension (its sector) and stays there, and is set to 0
    ///   for every other kind, so a radius, diameter or chamfer drag that writes it each step starts no refresh (an angle
    ///   dimension's drag still refreshes each step: its sector needs the topology);
    /// - hole callout: all of `placement`;
    /// - datum: `distance`, `dimensionEnd`; feature control frame and surface texture: `offset`;
    /// - balloon: `offset`; parts list: `bottomRight`; revision table: `topRight`;
    /// - note: `position` (a note is never refreshed, so the app's key drops it before this);
    /// - centre mark and centre line hold none, and so are returned as they are.
    ///
    /// Anything else stays: a symbol's or balloon's leader (its anchor and hint find the foot or name the part), a dimension's
    /// anchors, kind, tolerance, precision and text, and `last`. Adding a field to an annotation means deciding here whether
    /// `lastGood` reads it; a field left out of this function counts as read, which only costs a refresh.
    public var placementStripped: DrawingAnnotation {
        var stripped = self
        switch kind {
        case .dimension(var dimension):
            dimension.placement.offset = dimension.placement.offset >= 0 ? 5 : -5
            dimension.placement.textShift = nil
            if case .angle = dimension.kind {} else { dimension.placement.angle = 0 }
            stripped.kind = .dimension(dimension)
        case .holeCallout(var callout):
            callout.placement = DimensionPlacement(offset: 0, angle: 0)
            stripped.kind = .holeCallout(callout)
        case .note(var note):
            note.position = .zero
            stripped.kind = .note(note)
        case .datumFeature(var datum):
            datum.distance = 0
            datum.dimensionEnd = 0
            stripped.kind = .datumFeature(datum)
        case .featureControl(var frame):
            frame.offset = .zero
            stripped.kind = .featureControl(frame)
        case .surfaceTexture(var texture):
            texture.offset = nil
            stripped.kind = .surfaceTexture(texture)
        case .balloon(var balloon):
            balloon.offset = .zero
            stripped.kind = .balloon(balloon)
        case .partsList(var list):
            list.bottomRight = nil
            stripped.kind = .partsList(list)
        case .revisionTable(var table):
            table.topRight = nil
            stripped.kind = .revisionTable(table)
        case .centreMark, .centreLine:
            break
        }
        return stripped
    }
}
