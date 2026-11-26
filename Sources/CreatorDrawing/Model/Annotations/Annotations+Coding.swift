extension AnnotationKind: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, dimension, holeCallout, centreMark, centreLine, note, datumFeature, featureControl, surfaceTexture
        case balloon, partsList, revisionTable
    }

    // swiftlint:disable:next cyclomatic_complexity
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "dimension": self = .dimension(try c.decode(DrawingDimension.self, forKey: .dimension))
        case "holeCallout": self = .holeCallout(try c.decode(HoleCallout.self, forKey: .holeCallout))
        case "centreMark": self = .centreMark(try c.decode(CentreMark.self, forKey: .centreMark))
        case "centreLine": self = .centreLine(try c.decode(CentreLine.self, forKey: .centreLine))
        case "note": self = .note(try c.decode(DrawingNote.self, forKey: .note))
        case "datumFeature": self = .datumFeature(try c.decode(DatumFeature.self, forKey: .datumFeature))
        case "featureControl": self = .featureControl(try c.decode(FeatureControlFrame.self, forKey: .featureControl))
        case "surfaceTexture": self = .surfaceTexture(try c.decode(SurfaceTexture.self, forKey: .surfaceTexture))
        case "balloon": self = .balloon(try c.decode(Balloon.self, forKey: .balloon))
        case "partsList": self = .partsList(try c.decode(PartsList.self, forKey: .partsList))
        case "revisionTable": self = .revisionTable(try c.decode(RevisionTable.self, forKey: .revisionTable))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown annotation kind.")
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .dimension(let value):
            try c.encode("dimension", forKey: .type)
            try c.encode(value, forKey: .dimension)
        case .holeCallout(let value):
            try c.encode("holeCallout", forKey: .type)
            try c.encode(value, forKey: .holeCallout)
        case .centreMark(let value):
            try c.encode("centreMark", forKey: .type)
            try c.encode(value, forKey: .centreMark)
        case .centreLine(let value):
            try c.encode("centreLine", forKey: .type)
            try c.encode(value, forKey: .centreLine)
        case .note(let value):
            try c.encode("note", forKey: .type)
            try c.encode(value, forKey: .note)
        case .datumFeature(let value):
            try c.encode("datumFeature", forKey: .type)
            try c.encode(value, forKey: .datumFeature)
        case .featureControl(let value):
            try c.encode("featureControl", forKey: .type)
            try c.encode(value, forKey: .featureControl)
        case .surfaceTexture(let value):
            try c.encode("surfaceTexture", forKey: .type)
            try c.encode(value, forKey: .surfaceTexture)
        case .balloon(let value):
            try c.encode("balloon", forKey: .type)
            try c.encode(value, forKey: .balloon)
        case .partsList(let value):
            try c.encode("partsList", forKey: .type)
            try c.encode(value, forKey: .partsList)
        case .revisionTable(let value):
            try c.encode("revisionTable", forKey: .type)
            try c.encode(value, forKey: .revisionTable)
        }
    }
}
