import CreatorDrawing
import CreatorGeometry
import CreatorGraph
import Foundation

/// A sheet as an AI client reads it (DR-5 R19): composed as an export composes it, after one wait over the evaluation and the
/// sheet's projections together.
extension DrawingSession {
    /// What the wait had landed by the time it ended.
    @MainActor
    private final class Landed {
        var contents: [ViewID: ViewContent] = [:]
        var facts: TitleBlockFacts?
    }

    /// The sheet `id` composed as it stands once the model has evaluated and its views are projected, or as it stands after `limit`:
    /// a view whose projection hasn't landed is the previous lines drawn as a pending view is, its annotations judged against the
    /// topology they had (DR-2 R25). Notices are off. `nil` when there is no such sheet.
    public func sheetSnapshot(
        _ id: SheetID, within limit: Duration
    ) async -> (picture: SheetPicture, facts: TitleBlockFacts, views: [ViewID: ViewStatus])? {
        guard let sheet = editor.document.sheet(id) else { return nil }
        let landed = Landed()
        let (stream, signal) = AsyncStream<Bool>.makeStream()
        let work = Task { @MainActor [weak self] in
            await self?.document.waitForEvaluation()
            guard let self, !Task.isCancelled else { return }
            await self.projectViews(of: sheet) { landed.contents[$0] = $1 }
            if !Task.isCancelled { landed.facts = await self.facts(for: sheet) }
            signal.yield(true)
            signal.finish()
        }
        let timer = Task {
            try? await Task.sleep(for: limit)
            signal.yield(false)
            signal.finish()
        }
        var finished = false
        for await done in stream {
            finished = done
            break
        }
        timer.cancel()
        if !finished { work.cancel() }
        var contents: [ViewID: ViewContent] = [:]
        var statuses: [ViewID: ViewStatus] = [:]
        for view in sheet.views {
            var content = landed.contents[view.id] ?? editor.contents[view.id] ?? ViewContent()
            if landed.contents[view.id] == nil { content.isPending = true }
            contents[view.id] = content
            statuses[view.id] = ViewStatus(content)
        }
        let facts = landed.facts ?? TitleBlockFacts(parts: partFacts())
        let picture = SheetComposer.compose(
            sheet, in: editor.document, contents: contents, facts: facts, notices: false, units: document.units,
            remembered: editor.remembered)
        return (picture, facts, statuses)
    }
}
