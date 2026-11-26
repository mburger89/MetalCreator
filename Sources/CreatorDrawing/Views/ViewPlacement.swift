import CreatorGeometry

/// Where views stand on a sheet and how they follow each other (plan R7).
public enum ViewPlacement {
    /// Each view's centre with aligned views holding their parent's coordinate, parents resolved first.
    public static func centers(in sheet: DrawingSheet) -> [ViewID: Vector2] {
        var result: [ViewID: Vector2] = [:]
        func resolve(_ view: DrawingView) -> Vector2 {
            if let known = result[view.id] { return known }
            var center = view.center
            if isAligned(view, in: sheet), let alignment = view.alignment, let parent = sheet.view(alignment.parent) {
                let at = resolve(parent)
                center = alignment.axis == .horizontal ? Vector2(view.center.x, at.y) : Vector2(at.x, view.center.y)
            }
            result[view.id] = center
            return center
        }
        for view in sheet.views { _ = resolve(view) }
        return result
    }

    /// Whether the view's alignment holds: it has a parent here and is not part of a cycle.
    private static func isAligned(_ view: DrawingView, in sheet: DrawingSheet) -> Bool {
        guard let alignment = view.alignment else { return false }
        var seen: Set<ViewID> = [view.id]
        var next: ViewID? = alignment.parent
        while let id = next {
            guard let parent = sheet.view(id) else { return false }
            if !seen.insert(id).inserted { return false }
            next = parent.alignment?.parent
        }
        return true
    }

    private static func descendants(of id: ViewID, in sheet: DrawingSheet) -> [ViewID] {
        var found: [ViewID] = []
        var frontier = [id]
        while let current = frontier.popLast() {
            for view in sheet.views
                where (view.alignment?.parent == current || view.derivation?.parent == current) && !found.contains(view.id)
                && view.id != id {
                found.append(view.id)
                frontier.append(view.id)
            }
        }
        return found
    }

    /// Moves a view by `delta`, its aligned and derived descendants with it (a visited set ends any cycle); an aligned view moves along its free axis only.
    public static func moving(_ id: ViewID, by delta: Vector2, in sheet: DrawingSheet) -> DrawingSheet {
        guard let view = sheet.view(id) else { return sheet }
        var applied = delta
        if isAligned(view, in: sheet), let axis = view.alignment?.axis {
            if axis == .horizontal { applied.y = 0 } else { applied.x = 0 }
        }
        let centers = centers(in: sheet)
        var result = sheet
        for moved in [id] + descendants(of: id, in: sheet) {
            guard var change = sheet.view(moved), let at = centers[moved] else { continue }
            change.center = at + applied
            result.setView(change)
        }
        return result
    }

    /// Mirrors every aligned view across its parent along its free axis; frames and alignments stay.
    public static func mirroredForStandardChange(_ sheet: DrawingSheet) -> DrawingSheet {
        let old = centers(in: sheet)
        var fresh: [ViewID: Vector2] = [:]
        func resolve(_ view: DrawingView) -> Vector2 {
            if let known = fresh[view.id] { return known }
            var center = old[view.id] ?? view.center
            if isAligned(view, in: sheet), let alignment = view.alignment, let parent = sheet.view(alignment.parent) {
                let was = old[parent.id] ?? parent.center
                let now = resolve(parent)
                let offset = center - was
                center = alignment.axis == .horizontal
                    ? Vector2(now.x - offset.x, now.y) : Vector2(now.x, now.y - offset.y)
            }
            fresh[view.id] = center
            return center
        }
        var result = sheet
        for view in sheet.views {
            var change = view
            change.center = resolve(view)
            result.setView(change)
        }
        return result
    }

    /// Removes a view; its children stay where they stand, free.
    public static func removing(_ id: ViewID, from sheet: DrawingSheet) -> DrawingSheet {
        let centers = centers(in: sheet)
        var result = sheet
        for view in sheet.views where view.alignment?.parent == id {
            var freed = view
            freed.center = centers[view.id] ?? view.center
            freed.alignment = nil
            result.setView(freed)
        }
        result.removeView(id)
        return result
    }
}
