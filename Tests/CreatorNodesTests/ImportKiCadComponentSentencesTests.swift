import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorPCB
import Foundation
import Testing
@testable import CreatorNodes

/// The component warnings in their words, and the cache's refusal to keep a stale read (no OpenCascade needed).
struct ImportKiCadComponentSentencesTests {
    @Test func noModelSentencesSingularAndPlural() {
        #expect(Problems(noModel: ["H1"]).sentences() == ["1 component has no 3D model: H1."])
        #expect(Problems(noModel: ["H1", "H2"]).sentences() == ["2 components have no 3D model: H1, H2."])
    }

    @Test func notFoundAndUnreadableSentences() {
        #expect(Problems(notFound: ["a.step"]).sentences() == ["1 model wasn't found: a.step."])
        #expect(Problems(notFound: ["a.step", "b.step"]).sentences() == ["2 models weren't found: a.step, b.step."])
        #expect(Problems(unreadable: ["a.step (x)"]).sentences() == ["1 model couldn't be read: a.step (x)."])
        #expect(Problems(unreadable: ["a (x)", "b (y)"]).sentences() == ["2 models couldn't be read: a (x), b (y)."])
        #expect(Problems(unreadable: ["a (x)", "a (x)"]).sentences() == ["1 model couldn't be read: a (x)."])
    }

    @Test func onlyEightNamesAreListed() {
        let names = (1...11).map { "C\($0)" }
        #expect(Problems(noModel: names).sentences()
            == ["11 components have no 3D model: C1, C2, C3, C4, C5, C6, C7, C8 … (and 3 more)."])
    }

    @Test func aNonPositiveScaleIsUnreadable() async throws {
        let kernel = FakeKernel()
        let solid = try await kernel.extrude(Profile2D(plane: .xy, outer: [
            .line(Vector2(0, 0), Vector2(1, 0)), .line(Vector2(1, 0), Vector2(1, 1)),
            .line(Vector2(1, 1), Vector2(0, 1)), .line(Vector2(0, 1), Vector2(0, 0)),
        ]), distance: 1, mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        let footprint = Footprint(reference: "U1", libraryID: "L:F", uuid: nil, isBack: false, place: .identity, holes: [], models: [])
        let setting = BoardComponents.Setting(board: KiCadBoard(footprints: [footprint]), origin: .zero, thickness: 1.6, frame: .xy,
                                              folder: "")
        var placer = Placer(setting: setting, kernel: kernel, cache: ComponentModelCache(), node: NodeID())
        let stamp = ImageStamp.file(path: "/x/m.step", modified: Date(), size: 1)
        placer.found["m.step"] = .solid(solid, ComponentModelCache.ReadKey(stamp: stamp, format: .step), name: "m.step", isCurrent: true)
        let flat = ModelReference(path: "m.step", offset: .zero, scale: Vector3(0, 1, 1), rotation: .zero, isHidden: false)
        let piece = try await placer.place(flat, of: 0)
        #expect(piece == nil)
        #expect(placer.problems.unreadable == ["m.step (its scale isn't positive)"])
    }

    @Test func aStaleReadIsNotKept() async throws {
        let kernel = FakeKernel()
        let solid = try await kernel.extrude(Profile2D(plane: .xy, outer: [
            .line(Vector2(0, 0), Vector2(1, 0)), .line(Vector2(1, 0), Vector2(1, 1)), .line(Vector2(1, 1), Vector2(0, 0)),
        ]), distance: 1, mode: .oneSided, tag: NodeTag(node: NodeID(), item: 0))
        let cache = ComponentModelCache()
        let key = ComponentModelCache.ReadKey(stamp: .file(path: "/x/m.step", modified: Date(), size: 1), format: .step)
        _ = try await cache.solid(for: key) { .init(solid: solid, isCurrent: false) }
        #expect(await cache.count == 0)
        _ = try await cache.solid(for: key) { .init(solid: solid) }
        #expect(await cache.count == 1)
        #expect(await cache.reads(containing: "/x/") == 2)
    }
}

struct ImportKiCadFolderTests {
    @Test func aWindowsFolderLosesItsLeadingSlash() {
        #expect(BoardComponents.normalisedFolder("/C:/b") == "C:/b")
        #expect(BoardComponents.normalisedFolder("/c:") == "c:")
        #expect(BoardComponents.normalisedFolder("/home/b") == "/home/b")
        #expect(BoardComponents.normalisedFolder("/a:b/c") == "/a:b/c")
        #expect(BoardComponents.normalisedFolder("") == "")
    }
}
