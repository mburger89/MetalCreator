// Test fixture file: a dimension editor that records what the viewport asks of it and answers what a test sets.
import CreatorViewport

/// Records every commit and menu action. `outcome` answers a commit; with `holdsCommits` a commit stays open until `release()`.
@MainActor
final class FakeDimensionEditor: DimensionEditing {
    struct Commit: Hashable {
        var text: String
        var id: OverlayDimensionID
    }

    struct Performed: Hashable {
        var action: HostMenuAction
        var id: OverlayDimensionID
    }

    /// What each dimension's box opens with; an ID with no entry is not editable.
    var contents: [OverlayDimensionID: DimensionValueBoxContent] = [:]
    var outcome = DimensionCommitOutcome.accepted
    var holdsCommits = false
    var menus: [OverlayDimensionID: [HostMenuAction]] = [:]
    /// What each dimension says on hover; an ID with no entry says nothing.
    var notes: [OverlayDimensionID: String] = [:]
    private(set) var contentRequests = 0
    private(set) var commits: [Commit] = []
    private(set) var performed: [Performed] = []
    private var held: CheckedContinuation<Void, Never>?

    func valueBoxContent(for id: OverlayDimensionID) -> DimensionValueBoxContent? {
        contentRequests += 1
        return contents[id]
    }

    func commitValue(_ text: String, to id: OverlayDimensionID) async -> DimensionCommitOutcome {
        commits.append(Commit(text: text, id: id))
        if holdsCommits {
            await withCheckedContinuation { held = $0 }
            held = nil
        }
        return outcome
    }

    func hoverNote(for id: OverlayDimensionID) -> String? { notes[id] }

    func menuActions(for id: OverlayDimensionID) -> [HostMenuAction] { menus[id] ?? [] }

    func performMenuAction(_ action: HostMenuAction, for id: OverlayDimensionID) {
        performed.append(Performed(action: action, id: id))
    }

    /// Returns once a commit is being held.
    func waitUntilHeld() async {
        while held == nil { await Task.yield() }
    }

    /// Lets the held commit answer.
    func release() {
        held?.resume()
    }
}
