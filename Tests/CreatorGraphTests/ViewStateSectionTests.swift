import CreatorGeometry
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// The section view's settings live in the view state like the camera: an optional key, no format bump, no edit.
@MainActor
struct ViewStateSectionTests {
    private func roundTrip(_ state: ViewState) throws -> ViewState {
        try JSONDecoder().decode(ViewState.self, from: JSONEncoder().encode(state))
    }

    @Test func aSectionRoundTrips() throws {
        let tag = TopoTag(node: NodeID(), item: 0, role: .endCap)
        let face = SectionSettings(isOn: true,
                                   reference: .face(FacePick(tags: [tag], normal: .unitZ, centroid: Vector3(1, 2, 3))),
                                   offset: 2.5, isFlipped: true)
        let origin = SectionSettings(isOn: false, reference: .origin(.yz), offset: -1, isFlipped: false)
        for settings in [face, origin] {
            let state = ViewState(section: settings)
            #expect(try roundTrip(state) == state)
        }
    }

    @Test func noSectionWritesNoKey() throws {
        let json = try #require(String(bytes: JSONEncoder().encode(ViewState()), encoding: .utf8))
        #expect(!json.contains("\"section\""))
    }

    @Test func anOlderFileHasNoSection() throws {
        let decoded = try JSONDecoder().decode(ViewState.self, from: Data(#"{"dock":"left"}"#.utf8))
        #expect(decoded.section == nil)
    }

    @Test func aDamagedSectionIsDropped() throws {
        let badReference = #"{"section":{"isOn":true,"reference":{"plane":"xy"},"offset":1,"isFlipped":false}}"#
        let badOffset = #"{"section":{"isOn":true,"reference":{"origin":"xy"},"offset":"x","isFlipped":false}}"#
        for json in [badReference, badOffset] {
            let decoded = try JSONDecoder().decode(ViewState.self, from: Data(json.utf8))
            #expect(decoded.section == nil)
        }
    }

    @Test func theDocumentKeepsItsSectionAndItIsNoEdit() throws {
        let document = DocumentModel(file: GraphFile(graph: graph([makeNode(ConstantNode.self)])), registry: testRegistry,
                                     kernel: FakeKernel())
        let contentBefore = document.content
        let settings = SectionSettings(isOn: true, reference: .origin(.xz), offset: 3, isFlipped: true)
        document.section = settings
        #expect(document.viewState.section == settings)
        #expect(document.content == contentBefore, "the section is view state, not content, so the document is not edited")
        #expect(!document.canUndo)
        document.section = SectionSettings(isOn: true, reference: .origin(.xy), offset: .nan, isFlipped: false)
        #expect(document.section == settings)
        let reopened = try DocumentModel(data: try document.fileData(), registry: testRegistry, kernel: FakeKernel())
        #expect(reopened.viewState.section == settings)
    }
}
