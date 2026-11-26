import CreatorGeometry
import CreatorKernel

extension DrawingSheet {
    /// Whether the view is pictorial and so takes no dimensions (R11): false for sections and auxiliary views, the orientation's
    /// own reading for base and projected views, and a detail reads its parent's. A cycle reads false.
    public func isPictorial(_ view: DrawingView) -> Bool {
        var visited: Set<ViewID> = []
        return pictorial(view, visited: &visited)
    }

    private func pictorial(_ view: DrawingView, visited: inout Set<ViewID>) -> Bool {
        switch view.kind {
        case .section, .auxiliary: return false
        case .base, .projected: return view.orientation.isIsometric
        case .detail:
            guard visited.insert(view.id).inserted else { return false }
            guard let parentID = view.derivation?.parent, let parent = self.view(parentID) else {
                return view.orientation.isIsometric
            }
            return pictorial(parent, visited: &visited)
        }
    }

    /// R12: a derived view whose derivation is missing or of the wrong case is dropped, a derivation on a base or projected view is
    /// removed, and derivation cycles are broken (the lowest id of each cycle goes). Input is sorted by id.
    static func droppingBrokenDerivations(_ sorted: [DrawingView]) -> [DrawingView] {
        var result: [DrawingView] = []
        for var view in sorted {
            switch view.kind {
            case .base, .projected:
                view.derivation = nil
                view.letter = nil
            case .section, .detail, .auxiliary:
                guard let derivation = view.derivation, derivation.matches(view.kind) else { continue }
            }
            result.append(view)
        }
        while let doomed = lowestInACycle(result) { result.removeAll { $0.id == doomed } }
        return result
    }

    private static func lowestInACycle(_ views: [DrawingView]) -> ViewID? {
        let parents = Dictionary(
            views.compactMap { view in view.derivation.map { (view.id, $0.parent) } },
            uniquingKeysWith: { first, _ in first })
        for view in views {
            var path = [view.id]
            var seen: Set<ViewID> = [view.id]
            var current = parents[view.id]
            while let next = current, parents[next] != nil || seen.contains(next) {
                if seen.contains(next) {
                    let start = path.firstIndex(of: next) ?? 0
                    return path[start...].min()
                }
                seen.insert(next)
                path.append(next)
                current = parents[next]
            }
        }
        return nil
    }

    /// R3 and R7: a section's orientation follows its cutter; letters are unique and every derived view has one.
    static func repairingDerivations(_ sorted: [DrawingView]) -> [DrawingView] {
        var result = sorted
        var used: Set<String> = []
        var needing: [Int] = []
        for index in result.indices where result[index].derivation != nil {
            if case .section(let line)? = result[index].derivation {
                result[index].orientation = .custom(SectionFrame.frame(for: line.cutter))
            }
            if let letter = result[index].letter, !letter.isEmpty, used.insert(letter).inserted { continue }
            result[index].letter = nil
            needing.append(index)
        }
        for index in needing {
            let letter = ViewLetters.next(avoiding: used)
            used.insert(letter)
            result[index].letter = letter
        }
        return result
    }
}

extension DrawingSheet {
    /// The views with every view after its parent (R14), otherwise in the sheet's order. A view whose parent is not on the sheet
    /// counts as a root; a walk that meets a view it has seen stops there, so a damaged cycle can't loop.
    public var viewsParentsFirst: [DrawingView] {
        var placed: Set<ViewID> = []
        var result: [DrawingView] = []
        for view in views where !placed.contains(view.id) {
            var chain: [DrawingView] = []
            var seen: Set<ViewID> = []
            var current: DrawingView? = view
            while let next = current, !placed.contains(next.id), seen.insert(next.id).inserted {
                chain.append(next)
                current = next.derivation.flatMap { self.view($0.parent) }
            }
            for member in chain.reversed() where placed.insert(member.id).inserted { result.append(member) }
        }
        return result
    }

    /// The view itself unless it is a detail; a detail's nearest ancestor that is not one (R14), `nil` when the walk leaves the sheet
    /// or meets a cycle.
    public func nearestNonDetail(of view: DrawingView) -> DrawingView? {
        var seen: Set<ViewID> = []
        var current = view
        while current.kind == .detail {
            guard seen.insert(current.id).inserted, let parent = current.derivation.flatMap({ self.view($0.parent) }) else {
                return nil
            }
            current = parent
        }
        return current
    }
}
