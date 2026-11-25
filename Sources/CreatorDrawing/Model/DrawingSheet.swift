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

    public init(
        id: SheetID = SheetID(), name: String, size: SheetSize = .a3, orientation: SheetOrientation = .landscape,
        scale: DrawingScale = DrawingScale(numerator: 1, denominator: 1), titleBlock: TitleBlock = TitleBlock(),
        views: [DrawingView] = []
    ) {
        self.id = id
        self.name = name
        self.size = size
        self.orientation = orientation
        self.scale = scale
        self.titleBlock = titleBlock
        self.views = views.sorted { $0.id < $1.id }
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

    public mutating func removeView(_ id: ViewID) {
        views.removeAll { $0.id == id }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, size, orientation, scale, titleBlock, views
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
        views = Self.repairingAlignments(decoded.sorted { $0.id < $1.id })
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
}
