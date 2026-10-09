import CreatorGeometry
import CreatorGraph

extension EditorModel {
    /// The grid a node added from the library is nudged along, off the nodes under it, in display canvas points.
    public static let libraryNudge = Vector2(24, 24)
    /// Rings of the nudge grid scanned outward from the centre before the node is added there anyway.
    static let maxLibraryRings = 40

    /// Whether the graph panel shows its node library. Saved with the document's view state; not an edit.
    public var showsLibrary: Bool { document.viewState.showsLibrary }

    /// The panel header's "Library" button.
    public func toggleLibrary() {
        document.viewState.showsLibrary.toggle()
    }

    public func setLibraryQuery(_ query: String) {
        libraryQuery = query
    }

    /// The library's types matching its search (the palette's search, `PaletteSearch`), by category.
    public var librarySections: [LibrarySection] {
        LibrarySection.grouping(PaletteSearch.entries(in: registry, matching: libraryQuery))
    }

    /// A type's inputs → outputs, for the library's hover help; `nil` for an unregistered type.
    public func librarySummary(of typeID: String) -> String? {
        registry[typeID].map(NodeTypeSummary.text)
    }

    /// The visible canvas's size in points, from the host's placement (without one,
    /// `GraphPanelLayout.fallbackCanvasSize`).
    public var visibleCanvasSize: Vector2 {
        canvasFrameInWindow?.size ?? GraphPanelLayout.fallbackCanvasSize
    }

    /// The middle of the visible canvas, in canvas-local screen points.
    public var visibleCanvasCentre: Vector2 { visibleCanvasSize * 0.5 }

    /// A click on a library type: adds it centred in the visible canvas, or at the nearest spot in view where it
    /// overlaps no other node, and selects it, as one undo step.
    public func addFromLibrary(_ typeID: String) {
        guard registry[typeID] != nil else { return }
        var node = registry.makeNode(typeID)
        let size = NodeLayout.size(shape(of: node))
        let centred = transform.toCanvas(visibleCanvasCentre) - size * 0.5
        let visible = CanvasRect(corner: transform.toCanvas(.zero), transform.toCanvas(visibleCanvasSize))
        node.position = flow.stored(freeOrigin(near: centred, size: size, in: visible))
        add(node)
    }

    /// A library type dropped on the canvas at `screen` (canvas-local screen points): its top-left corner lands
    /// there, as one undo step. Returns false, adding nothing, for a type that isn't registered.
    @discardableResult
    public func dropFromLibrary(_ typeID: String, atScreen screen: Vector2) -> Bool {
        guard registry[typeID] != nil, screen.isFinite else { return false }
        addNode(typeID, atScreen: screen)
        return true
    }

    /// The pointer moved while pressing a library type's row (`start` and `location` in window points). Once it is
    /// `LibraryDrag.threshold` from the press the type is being dragged, and `LibraryDragOverlay` draws it at the
    /// pointer; short of that nothing changes, so a click's jitter rebuilds nothing.
    public func moveLibraryDrag(_ typeID: String, from start: Vector2, to location: Vector2) {
        let drag = LibraryDrag(typeID: typeID, start: start, location: location)
        let shown = drag.isDragging ? drag : nil
        if libraryDrag != shown { libraryDrag = shown }
    }

    /// The press on a library type's row ended at `location` (window points). Short of `LibraryDrag.threshold` it was
    /// a click: the type is added at the visible canvas's centre (`addFromLibrary(_:)`). Otherwise it was dragged: it
    /// is added with its top-left corner at the release point when that is on the canvas (`canvasFrameInWindow`, which
    /// leaves out the library), and nothing is added anywhere else or before the host has placed the panel. Each add
    /// is one undo step. Returns whether a node was added.
    @discardableResult
    public func endLibraryDrag(_ typeID: String, from start: Vector2, at location: Vector2) -> Bool {
        if libraryDrag != nil { libraryDrag = nil }
        guard registry[typeID] != nil else { return false }
        guard LibraryDrag(typeID: typeID, start: start, location: location).isDragging else {
            addFromLibrary(typeID)
            return true
        }
        guard let canvas = canvasFrameInWindow, canvas.contains(location) else { return false }
        return dropFromLibrary(typeID, atScreen: location - canvas.origin)
    }

    /// The type the drag ghost shows, while a library type is being dragged.
    public var libraryDragEntry: PaletteEntry? {
        guard let drag = libraryDrag, let definition = registry[drag.typeID] else { return nil }
        return PaletteEntry(typeID: definition.typeID, displayName: definition.displayName, category: definition.category)
    }

    /// The nearest display origin to `start` on the `libraryNudge` grid, scanned ring by ring outward, where a `size`
    /// node lies inside `visible` (the visible canvas, in display canvas points) and meets no node's frame; `start`
    /// itself when none does within `maxLibraryRings`, so the node still lands in the middle of the view.
    func freeOrigin(near start: Vector2, size: Vector2, in visible: CanvasRect) -> Vector2 {
        let frames = graph.nodes.values.map(frame(of:))
        func fits(_ origin: Vector2) -> Bool {
            let candidate = CanvasRect(origin: origin, size: size)
            return visible.contains(origin) && visible.contains(origin + size)
                && !frames.contains { $0.intersects(candidate) }
        }
        for ring in 0...Self.maxLibraryRings {
            for row in -ring...ring {
                for column in -ring...ring where max(abs(row), abs(column)) == ring {
                    let origin = start + Vector2(Self.libraryNudge.x * Double(column), Self.libraryNudge.y * Double(row))
                    if fits(origin) { return origin }
                }
            }
        }
        return start
    }
}
