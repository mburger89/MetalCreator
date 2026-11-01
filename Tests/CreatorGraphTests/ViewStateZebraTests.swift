import CreatorGeometry
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

/// The zebra view's settings live in the view state like the section: an optional key, no format bump, no edit.
@MainActor
struct ViewStateZebraTests {
    private func roundTrip(_ state: ViewState) throws -> ViewState {
        try JSONDecoder().decode(ViewState.self, from: JSONEncoder().encode(state))
    }

    private let frame = ZebraFrame(right: Vector3(1, 0, 0), up: Vector3(0, 1, 0), toEye: Vector3(0, 0, 1))

    @Test func zebraRoundTrips() throws {
        let locked = ZebraSettings(isOn: true, direction: .vertical, stripes: 20, blackShare: 0.3, lock: frame)
        for settings in [locked, ZebraSettings()] {
            let state = ViewState(zebra: settings)
            #expect(try roundTrip(state) == state)
        }
    }

    @Test func noZebraWritesNoKey() throws {
        let json = try #require(String(bytes: JSONEncoder().encode(ViewState()), encoding: .utf8))
        #expect(!json.contains("\"zebra\""))
    }

    @Test func anOlderFileHasNoZebra() throws {
        let decoded = try JSONDecoder().decode(ViewState.self, from: Data(#"{"dock":"left"}"#.utf8))
        #expect(decoded.zebra == nil)
    }

    @Test func aDamagedZebraIsDropped() throws {
        let badDirection = #"{"zebra":{"isOn":true,"direction":"diagonal","stripes":12,"blackShare":0.5}}"#
        let badStripes = #"{"zebra":{"isOn":true,"direction":"vertical","stripes":"x","blackShare":0.5}}"#
        for json in [badDirection, badStripes] {
            let decoded = try JSONDecoder().decode(ViewState.self, from: Data(json.utf8))
            #expect(decoded.zebra == nil)
        }
    }

    @Test func outOfRangeValuesAreClamped() throws {
        #expect(ZebraSettings(stripes: 2).stripes == 4)
        #expect(ZebraSettings(stripes: 99).stripes == 40)
        #expect(ZebraSettings(blackShare: 0.05).blackShare == 0.2)
        #expect(ZebraSettings(blackShare: 0.95).blackShare == 0.8)
        let json = #"{"zebra":{"isOn":true,"direction":"horizontal","stripes":2,"blackShare":0.05}}"#
        let decoded = try #require(try JSONDecoder().decode(ViewState.self, from: Data(json.utf8)).zebra)
        #expect(decoded.stripes == 4)
        #expect(decoded.blackShare == 0.2)
        let high = #"{"zebra":{"stripes":99,"blackShare":0.9}}"#
        let decodedHigh = try #require(try JSONDecoder().decode(ViewState.self, from: Data(high.utf8)).zebra)
        #expect(decodedHigh.stripes == 40)
        #expect(decodedHigh.blackShare == 0.8)
    }

    @Test func aNonFiniteLockIsRefused() {
        let document = DocumentModel(file: GraphFile(graph: graph([makeNode(ConstantNode.self)])), registry: testRegistry,
                                     kernel: FakeKernel())
        let settings = ZebraSettings(isOn: true, lock: frame)
        document.zebra = settings
        let bad = ZebraFrame(right: Vector3(.nan, 0, 0), up: Vector3(0, 1, 0), toEye: Vector3(0, 0, 1))
        document.zebra = ZebraSettings(isOn: true, lock: bad)
        #expect(document.zebra == settings)
    }

    @Test func aNonUnitLockIsDropped() throws {
        let json = #"{"zebra":{"isOn":true,"lock":{"right":{"x":2,"y":0,"z":0},"up":{"x":0,"y":1,"z":0},"toEye":{"x":0,"y":0,"z":1}}}}"#
        let decoded = try #require(try JSONDecoder().decode(ViewState.self, from: Data(json.utf8)).zebra)
        #expect(decoded.isOn && decoded.lock == nil)
        let state = ViewState(zebra: ZebraSettings(isOn: true, lock: frame))
        let good = try JSONDecoder().decode(ViewState.self, from: JSONEncoder().encode(state))
        #expect(good.zebra?.lock == frame)
    }

    @Test func theDocumentKeepsItsZebraAndItIsNoEdit() throws {
        let document = DocumentModel(file: GraphFile(graph: graph([makeNode(ConstantNode.self)])), registry: testRegistry,
                                     kernel: FakeKernel())
        let contentBefore = document.content
        let settings = ZebraSettings(isOn: true, direction: .vertical, stripes: 8, blackShare: 0.6, lock: frame)
        document.zebra = settings
        #expect(document.viewState.zebra == settings)
        #expect(document.content == contentBefore, "zebra is view state, not content, so the document is not edited")
        #expect(!document.canUndo)
        let reopened = try DocumentModel(data: try document.fileData(), registry: testRegistry, kernel: FakeKernel())
        #expect(reopened.viewState.zebra == settings)
    }
}
