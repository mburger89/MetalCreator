import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorViewport
#if canImport(CreatorOCCT)
@testable import CreatorOCCT
#endif

#if canImport(CreatorOCCT)
/// NS-3 Task 9: the list sentence goes with the wire, and the demand the net asked for is always given back.
extension ControlNetModeTests {
    @Test func removingAListWireClearsItsSentence() async throws {
        let fixture = await open(["count": .integer(3)])
        fixture.app.editControlPoints(of: fixture.edit.id)
        await fixture.app.settle()
        fixture.app.editor.selection = [fixture.edit.id]
        await fixture.app.settle()
        #expect(fixture.app.controlNetProblem == "Edit Control Points works on one surface; this node gets 3.")
        let link = try #require(fixture.app.document.graph.links.first { $0.to.node == fixture.edit.id })
        try fixture.app.document.perform(.disconnect(link), name: UndoName.changeParameter)
        await fixture.app.settle()
        #expect(fixture.app.controlNetProblem == nil)
    }

    @Test func demandIsGivenBackAfterDoneEscAndDeselecting() async throws {
        let fixture = await open()
        let before = fixture.app.document.extraDemand
        let first = try await enter(fixture)
        #expect(fixture.app.document.extraDemand == fixture.source.id)
        first.done()
        fixture.app.editor.selection = []
        await fixture.app.settle()
        #expect(fixture.app.document.extraDemand == before)

        let second = try await enter(fixture)
        second.cancel()
        second.cancel()
        fixture.app.editor.selection = []
        await fixture.app.settle()
        #expect(fixture.app.controlNet == nil)
        #expect(fixture.app.document.extraDemand == before)

        fixture.app.editor.selection = [fixture.edit.id]
        await fixture.app.settle()
        #expect(fixture.app.document.extraDemand == fixture.source.id)
        fixture.app.editor.selection = []
        await fixture.app.settle()
        #expect(fixture.app.document.extraDemand == before)
    }
}
#endif
