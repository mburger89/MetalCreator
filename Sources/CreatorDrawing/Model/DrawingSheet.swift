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

    /// Removes the annotation and the symbols hanging on it (plan R2).
    public mutating func removeAnnotation(_ id: AnnotationID) {
        annotations.removeAll { $0.id == id || $0.symbolAttachment == .dimension(id) }
    }

    /// The symbols hanging on a dimension, in sheet order.
    public func symbols(on dimension: AnnotationID) -> [DrawingAnnotation] {
        annotations.filter { $0.symbolAttachment == .dimension(dimension) }
    }

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
            decodedAnnotations.filter { $0.view.map(present.contains) ?? true }.sorted { $0.id < $1.id })
        notes = try c.decodeIfPresent(SheetNotes.self, forKey: .notes) ?? SheetNotes()
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

    /// A view whose alignment names a view that is not here, or would close a cycle, is kept and set free at its centre.
    private static func repairingAlignments(_ sorted: [DrawingView]) -> [DrawingView] {
        var result = sorted
        let present = Set(sorted.map(\.id))
        for index in result.indices {
            if let parent = result[index].alignment?.parent, !present.contains(parent) { result[index].alignment = nil }
        }
        for index in result.indices where result[index].alignment != nil {
            var seen: Set<ViewID> = [result[index].id]
            var next = result[index].alignment?.parent
            while let current = next {
                if !seen.insert(current).inserted {
                    result[index].alignment = nil
                    break
                }
                next = result.first { $0.id == current }?.alignment?.parent
            }
        }
        return result
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
