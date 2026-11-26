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
