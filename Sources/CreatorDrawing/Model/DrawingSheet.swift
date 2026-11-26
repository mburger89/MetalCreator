import CreatorGeometry

/// One sheet of a drawing: its paper, scale, title block and views (kept sorted by id).
public struct DrawingSheet: Hashable, Sendable, Codable, Identifiable {
    public var id: SheetID
    public var name: String
    public var size: SheetSize
    public var orientation: SheetOrientation
    public var scale: DrawingScale
    public var titleBlock: TitleBlock
    public private(set) var views: [DrawingView]
    /// The sheet's annotations, sorted by id (plan R2).
    public private(set) var annotations: [DrawingAnnotation]
    /// General notes, the edge break and the general surface requirement (plan R12).
    public var notes: SheetNotes

    public init(
        id: SheetID = SheetID(), name: String, size: SheetSize = .a3, orientation: SheetOrientation = .landscape,
        scale: DrawingScale = DrawingScale(numerator: 1, denominator: 1), titleBlock: TitleBlock = TitleBlock(),
        views: [DrawingView] = [], annotations: [DrawingAnnotation] = [],
        notes: SheetNotes = SheetNotes()
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.orientation = orientation
        self.scale = scale
        self.titleBlock = titleBlock
        self.views = views.sorted { $0.id < $1.id }
        self.annotations = annotations.sorted { $0.id < $1.id }
        self.notes = notes
    }

    /// The paper in millimetres, width by height; landscape swaps the upright size.
    public var paperSize: Vector2 {
        let upright = size.portrait
        return orientation == .landscape ? Vector2(upright.y, upright.x) : upright
    }

    public func view(_ id: ViewID) -> DrawingView? { views.first { $0.id == id } }

    /// Adds the view, or replaces the one with its id, keeping the list sorted.
    public mutating func setView(_ view: DrawingView) {
        if let index = views.firstIndex(where: { $0.id == view.id }) {
            views[index] = view
        } else {
            let at = views.firstIndex { $0.id > view.id } ?? views.endIndex
            views.insert(view, at: at)
        }
    }

    /// Removes the view and, with it, its annotations (plan R27); free annotations stay.
    public mutating func removeView(_ id: ViewID) {
        views.removeAll { $0.id == id }
        annotations.removeAll { $0.view == id }
    }

    public func annotation(_ id: AnnotationID) -> DrawingAnnotation? { annotations.first { $0.id == id } }

    public func annotations(of view: ViewID) -> [DrawingAnnotation] { annotations.filter { $0.view == view } }

    /// Adds the annotation, or replaces the one with its id, keeping the list sorted.
    public mutating func setAnnotation(_ annotation: DrawingAnnotation) {
        if let index = annotations.firstIndex(where: { $0.id == annotation.id }) {
            annotations[index] = annotation
        } else {
            let at = annotations.firstIndex { $0.id > annotation.id } ?? annotations.endIndex
            annotations.insert(annotation, at: at)
        }
    }

    /// Every datum symbol's stored distance made the one drawn (at least `DatumLayout.minimumDistance`), so the stored and the drawn
    /// values agree. `standard` gives the lettering height; decoding does not know it and takes the smaller of the two.
    public mutating func clampingDatumDistances(standard: DrawingStandard?) {
        let heights = [DrawingStyle.iso, .asme].filter { standard == nil || $0.standard == standard }.map { $0.notesHeight(for: size) }
        guard let h = heights.min() else { return }
        for index in annotations.indices {
            guard case .datumFeature(var datum) = annotations[index].kind else { continue }
            let clamped = datum.clampedDistance(h: h)
            guard clamped != datum.distance else { continue }
            datum.distance = clamped
            annotations[index].kind = .datumFeature(datum)
        }
    }

    /// Removes the annotation and the symbols hanging on it (plan R2).
    public mutating func removeAnnotation(_ id: AnnotationID) {
        annotations.removeAll { $0.id == id || $0.symbolAttachment == .dimension(id) }
    }

    /// The symbols hanging on a dimension, in sheet order.
    public func symbols(on dimension: AnnotationID) -> [DrawingAnnotation] {
        annotations.filter { $0.symbolAttachment == .dimension(dimension) }
    }

    /// The sheet's parts list, if it has one (DR-5 R7); at most one.
    public var partsList: (id: AnnotationID, list: PartsList)? {
        for annotation in annotations {
            if case .partsList(let list) = annotation.kind { return (annotation.id, list) }
        }
        return nil
    }

    /// The sheet's revision table, if it has one (DR-5 R9); at most one.
    public var revisionTable: (id: AnnotationID, table: RevisionTable)? {
        for annotation in annotations {
            if case .revisionTable(let table) = annotation.kind { return (annotation.id, table) }
        }
        return nil
    }

    /// The letter of the table's last row whose letter is a valid revision letter; nil with no table or no valid row.
    public var lastValidRevisionLetter: String? {
        revisionTable?.table.rows.last { RevisionLetters.isValid($0.letter) }?.letter
    }

    /// What the title block's revision field shows: the table's last valid letter, else the typed revision (DR-5 R9).
    public var revisionShown: String { lastValidRevisionLetter ?? titleBlock.revision }

    private enum CodingKeys: String, CodingKey {
        case id, name, size, orientation, scale, titleBlock, views, annotations, notes
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(SheetID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        size = try c.decode(SheetSize.self, forKey: .size)
        orientation = try c.decode(SheetOrientation.self, forKey: .orientation)
        // A damaged scale (a zero or a huge side) would put infinities on screen: it reads 1 : 1.
        let decodedScale = try c.decode(DrawingScale.self, forKey: .scale)
        scale = decodedScale.isValid ? decodedScale : DrawingScale(numerator: 1, denominator: 1)
        titleBlock = try c.decodeIfPresent(TitleBlock.self, forKey: .titleBlock) ?? TitleBlock()
        let decoded = try c.decodeIfPresent([DrawingView].self, forKey: .views) ?? []
        views = Self.repairingDerivations(Self.repairingAlignments(Self.droppingBrokenDerivations(decoded.sorted { $0.id < $1.id })))
        // An annotation of a view that is not on the sheet is dropped.
        let present = Set(views.map(\.id))
        let decodedAnnotations = try c.decodeIfPresent([DrawingAnnotation].self, forKey: .annotations) ?? []
        annotations = Self.repairingSymbols(
            Self.repairingTables(
                decodedAnnotations.map(Self.freeingTables).filter { $0.view.map(present.contains) ?? true }.sorted { $0.id < $1.id }))
        notes = try c.decodeIfPresent(SheetNotes.self, forKey: .notes) ?? SheetNotes()
        clampingDatumDistances(standard: nil)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(size, forKey: .size)
        try c.encode(orientation, forKey: .orientation)
        try c.encode(scale, forKey: .scale)
        try c.encode(titleBlock, forKey: .titleBlock)
        try c.encode(views, forKey: .views)
        if !annotations.isEmpty { try c.encode(annotations, forKey: .annotations) }
        if !notes.isEmpty { try c.encode(notes, forKey: .notes) }
    }

    /// A view whose alignment names a view that is not here, or that is the highest `ViewID` of a cycle, is kept and set free at
    /// its centre; every other view keeps its alignment, though it follows a free view (`ViewPlacement.alignmentIsBroken`).
    private static func repairingAlignments(_ sorted: [DrawingView]) -> [DrawingView] {
        var result = sorted
        for index in result.indices where ViewPlacement.alignmentIsBroken(sorted[index], in: sorted) {
            result[index].alignment = nil
        }
        return result
    }

    /// A parts list or revision table is free on the sheet: one that names a view reads as free (DR-5 R17).
    private static func freeingTables(_ annotation: DrawingAnnotation) -> DrawingAnnotation {
        switch annotation.kind {
        case .partsList, .revisionTable:
            var freed = annotation
            freed.view = nil
            return freed
        default: return annotation
        }
    }

    /// A balloon with no view is dropped, and so is a second parts list or revision table, the first by id kept (DR-5 R17).
    private static func repairingTables(_ sorted: [DrawingAnnotation]) -> [DrawingAnnotation] {
        var haveList = false
        var haveTable = false
        return sorted.filter { annotation in
            switch annotation.kind {
            case .balloon: return annotation.view != nil
            case .partsList:
                defer { haveList = true }
                return !haveList
            case .revisionTable:
                defer { haveTable = true }
                return !haveTable
            default: return true
            }
        }
    }

    /// Plan R14: a symbol with no view, or on a dimension that is missing, of another view or of a kind it cannot take, is
    /// dropped; a frame keeps at most two rows (one when its characteristic takes no composite) and a row at most three datums.
    private static func repairingSymbols(_ sorted: [DrawingAnnotation]) -> [DrawingAnnotation] {
        let byID = Dictionary(sorted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [DrawingAnnotation] = []
        for var annotation in sorted {
            guard let kind = annotation.symbolKind else {
                result.append(annotation)
                continue
            }
            guard annotation.view != nil else { continue }
            if case .dimension(let id)? = annotation.symbolAttachment {
                guard let target = byID[id], target.view == annotation.view, SymbolAttachment.accepts(kind, on: target) else { continue }
            }
            if case .featureControl(var frame) = annotation.kind {
                guard !frame.rows.isEmpty else { continue }
                frame.rows = Array(frame.rows.prefix(frame.characteristic.allowsComposite ? 2 : 1))
                for row in frame.rows.indices { frame.rows[row].datums = Array(frame.rows[row].datums.prefix(3)) }
                annotation.kind = .featureControl(frame)
            }
            result.append(annotation)
        }
        return result
    }
}
