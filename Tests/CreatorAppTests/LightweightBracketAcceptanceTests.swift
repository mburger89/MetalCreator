#if canImport(CreatorOCCT)
import CreatorGeometry
import CreatorGraph
import CreatorImplicit
import CreatorKernel
import CreatorNodes
import Foundation
import Testing
@testable import CreatorApp
@testable import CreatorOCCT

/// Implicit spec §7's acceptance test, headless on OCCT: a lightweight bracket. The slice's bracket (spec §7.2, as `makeBracketBenchApp` builds
/// it) → To Implicit → TPMS (Gyroid, Sheet, thickness graded by a distance field, skin 1.5 mm) → Drain Holes (Automatic) → Mesh (0.3 mm) →
/// Check Thin Walls → Check Trapped Volumes → Output, exported as 3MF. It asserts a closed manifold, no enclosed void, no wall under the
/// minimum, a volume between 15% and 75% of the solid's (the spec says 40%; see Task 12), and identical bytes on a second run. The TPMS
/// node joins its skin and its sheet with the default `blend` of 1 mm (Errata D18).
///
/// **It needs 7c-2's TPMS node** (`TPMSNode`, `TPMSType`, `TPMSForm`), so it joins the plan only after 7c-2 has merged; whichever of 7c-2 and 7c-3
/// merges second adds this file.
@MainActor
struct LightweightBracketAcceptanceTests {
    nonisolated static let minimumWall = 0.4

    /// The nodes this test adds to the bracket's document.
    struct Lightweight {
        var thin: Node
        var traps: Node
        var output: Node
        var all: [Node]
    }

    func add(_ app: AppModel, _ definition: any NodeDefinition.Type, _ values: [SocketName: ConstantValue] = [:]) throws -> Node {
        var node = app.registry.makeNode(definition.typeID, at: Vector2(Double(app.document.graph.nodes.count) * 40, 300))
        node.inputValues.merge(values) { _, given in given }
        try app.document.perform(.addNode(node))
        return node
    }

    func wire(_ app: AppModel, _ from: Node, _ output: SocketName, _ to: Node, _ input: SocketName) throws {
        try app.document.perform(.connect(Link(from: Endpoint(node: from.id, socket: output), to: Endpoint(node: to.id, socket: input))))
    }

    /// Replaces the bracket's solid Output by the lightweight chain.
    func buildLightweight(on app: AppModel, from bracket: AppBracket, cellSize: Double = 10, thickest: Double = 1.2,
                          thinnest: Double = 0.8, drain diameter: Double = 2) throws -> Lightweight {
        try app.document.perform(.removeNode(bracket.output.id))
        let toImplicit = try add(app, ToImplicitNode.self, ["tolerance": .number(0.05)])
        // The thickness follows the distance from the surface: 1.2 mm at the skin, 0.8 mm eight millimetres in.
        let distance = try add(app, DistanceFieldNode.self, ["mode": .integer(0)])
        let grading = try add(app, FieldRemapNode.self, [
            "fromLow": .number(0), "fromHigh": .number(8), "toLow": .number(thickest), "toHigh": .number(thinnest),
        ])
        let lattice = try add(app, TPMSNode.self, [
            "type": .integer(TPMSType.gyroid.rawValue), "form": .integer(TPMSForm.sheet.rawValue), "cell size": .number(cellSize),
            "skin": .number(1.5),
        ])
        let drain = try add(app, DrainHolesNode.self, ["diameter": .number(diameter)])
        let mesh = try add(app, MeshNode.self, ["export resolution": .number(0.3)])
        let thin = try add(app, CheckThinWallsNode.self, ["minimum": .number(Self.minimumWall)])
        let traps = try add(app, CheckTrappedVolumesNode.self)
        let output = try add(app, OutputNode.self)
        try app.document.perform(.rename(output.id, "Lightweight Bracket"))
        try wire(app, bracket.chamfer, "solid", toImplicit, "solid")
        try wire(app, bracket.chamfer, "solid", distance, "target")
        try wire(app, distance, "field", grading, "field")
        try wire(app, toImplicit, "implicit", lattice, "region")
        try wire(app, grading, "field", lattice, "thickness")
        try wire(app, lattice, "implicit", drain, "implicit")
        try wire(app, drain, "implicit", mesh, "implicit")
        try wire(app, mesh, "mesh", thin, "mesh")
        try wire(app, thin, "mesh", traps, "mesh")
        try wire(app, traps, "mesh", output, "mesh")
        return Lightweight(thin: thin, traps: traps, output: output,
                           all: [toImplicit, distance, grading, lattice, drain, mesh, thin, traps, output])
    }

    nonisolated static func voidCount(of mesh: TriangleMesh) throws -> Int {
        try TrappedVolumeCheck.run(mesh).voidCount
    }

    nonisolated static func thinPlaces(of mesh: TriangleMesh) throws -> Int {
        try ThinWallCheck.run(mesh, minimum: minimumWall).places
    }

    @Test func aLightweightBracketIsDrainedCheckedAndExportedAs3MF() async throws {
        let (app, bracket) = try await makeBracketBenchApp()
        let solid = try #require(app.document.results[bracket.chamfer.id]?.outputs?["solid"]?.items.first)
        guard case .solid(let part) = solid else { Issue.record("the bracket made no solid"); return }
        let solidVolume = try await app.kernel.properties(of: part).volume
        let chain = try buildLightweight(on: app, from: bracket)
        await app.settle()
        for node in chain.all {
            if case .error(let message)? = app.document.results[node.id]?.state { Issue.record("“\(node.name)”: \(message)") }
        }

        let first = temporaryURL("lightweight-1.3mf"), second = temporaryURL("lightweight-2.3mf")
        defer { for url in [first, second] { try? FileManager.default.removeItem(at: url) } }
        try await app.export(.threeMF, to: first)
        // The summary lists the warnings of the nodes the file came from.
        let summary: String
        if case .problem(let problem)? = app.alert { summary = problem.message } else { summary = "" }
        app.alert = nil
        try await app.export(.threeMF, to: second)
        #expect(try Data(contentsOf: first) == Data(contentsOf: second), "the same bytes on a second run")

        let objects = try ExportStreamedTests().objects(first)
        #expect(objects.map(\.name) == ["Lightweight Bracket"])
        let mesh = try #require(objects.first?.mesh)
        #expect(MeshTopology(mesh).isClosedManifold, "\(MeshTopology(mesh))")
        // Spec §7 asks for 0 of each. Errata M5 measured 103 voids and 127 thin places here; Errata D18 found them to be phantoms of the
        // sharp skin join and of the checks, and the lattice's default 1 mm blend and the robust checks removed them.
        // The two checks are independent, so they run side by side (each in a plain function, off the main actor).
        async let voidCount = Self.voidCount(of: mesh)
        async let thinCount = Self.thinPlaces(of: mesh)
        let (voids, thinPlaces) = try await (voidCount, thinCount)
        print("LIGHTWEIGHT voids \(voids), thin places \(thinPlaces), volume fraction \(mesh.signedVolume / solidVolume)")
        #expect(voids == 0, "the drain holes opened every void")
        #expect(thinPlaces == 0, "no wall under \(Self.minimumWall) mm")
        #expect(!summary.contains("Walls thinner"), "\(summary)")
        let fraction = mesh.signedVolume / solidVolume
        #expect(fraction > 0.15 && fraction < 0.75, "the part is \(fraction) of the solid's volume")
    }
}
#endif
