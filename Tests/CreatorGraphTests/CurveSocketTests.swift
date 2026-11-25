import CreatorGeometry
import Foundation
import Testing
@testable import CreatorGraph
@testable import CreatorKernel

struct CurveSocketTests {
    @Test func aCurveSocketAcceptsCurvesAndProfiles() {
        #expect(SocketType.curve.accepts(.profile) && SocketType.curve.accepts(.curve))
        #expect(!SocketType.solid.accepts(.curve))
        #expect(!SocketType.curve.accepts(.solid))
        #expect(SocketType.curve.indefiniteName == "a curve")
    }

    @Test func aProfileStaysAProfileOnACurveSocket() {
        let profile = Profile2D(plane: .xy, segments: [])
        guard case .profile? = Scalar.profile(profile).converted(to: .curve) else { Issue.record("converted"); return }
    }

    @Test func aGroupInterfaceCarriesACurveSocketAtFormat14() throws {
        #expect(GraphFile.currentFormatVersion == 17)
        var group = Doubler()
        group.definition.inputs = [SocketSpec("path", .curve, access: .list, optional: true)]
        let file = GraphFile(graph: Graph(), definitions: [group.definition.id: group.definition])
        let data = try GraphFileIO.encode(file)
        let back = try GraphFileIO.decode(data, registry: testRegistry)
        #expect(back.formatVersion == 17)
        #expect(back.definitions[group.definition.id]?.inputs == group.definition.inputs)
        #expect(try #require(String(bytes: data, encoding: .utf8)).contains("\"curve\""))
    }

    @Test func aFormat13FileOpensUnchanged() throws {
        let json = #"{"formatVersion": 13, "graph": {"nodes": []}}"#
        let file = try GraphFileIO.decode(Data(json.utf8), registry: testRegistry)
        #expect(file.graph == Graph())
    }
}
