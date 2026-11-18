import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import Testing
#if canImport(CreatorOCCT)
import CreatorOCCT
#endif

/// NS-2 Task 3: the Network Surface node.
struct NetworkSurfaceNodeTests {
    /// A straight curve from two points: a Vector over a two-point Series on one axis.
    func line(_ h: inout Harness, axis: SocketName, fixed: [SocketName: Double]) -> Node {
        let series = h.add(SeriesNode.self, ["step": .number(10), "count": .integer(2)])
        let vector = h.add(VectorNode.self, Dictionary(uniqueKeysWithValues: fixed.map { ($0.key, ConstantValue.number($0.value)) }))
        h.wire(series, "values", to: vector, axis)
        let curve = h.add(CurveThroughPointsNode.self)
        h.wire(vector, "vector", to: curve, "points")
        return curve
    }

    func grid(_ h: inout Harness) -> Node {
        let node = h.add(NetworkSurfaceNode.self)
        let sockets: [SocketName] = ["a", "b", "c"]
        let us = h.add(MergeNode.self), vs = h.add(MergeNode.self)
        for (index, value) in [0.0, 5, 10].enumerated() {
            h.wire(line(&h, axis: "x", fixed: ["y": value]), "curve", to: us, sockets[index])
            h.wire(line(&h, axis: "y", fixed: ["x": value]), "curve", to: vs, sockets[index])
        }
        h.wire(us, "list", to: node, "u curves")
        h.wire(vs, "list", to: node, "v curves")
        return node
    }

    @Test func theNodeIsInTheSurfaceLibraryUnderMake() {
        #expect(NetworkSurfaceNode.category == .surface && NetworkSurfaceNode.librarySubgroup == "Make")
        #expect(NetworkSurfaceNode.inputs.first { $0.name == "tolerance" }?.defaultValue == .number(0.01))
    }

    @Test func tooManyCurvesAreRefusedBeforeAnyKernelWork() async throws {
        var h = Harness()
        let u = h.add(SeriesNode.self, ["start": .number(1), "count": .integer(1_001)])
        let v = h.add(SeriesNode.self, ["start": .number(1), "count": .integer(1_000)])
        let ur = h.add(RectangleNode.self), vr = h.add(RectangleNode.self)
        h.wire(u, "values", to: ur, "width")
        h.wire(v, "values", to: vr, "width")
        let node = h.add(NetworkSurfaceNode.self)
        h.wire(ur, "profile", to: node, "u curves")
        h.wire(vr, "profile", to: node, "v curves")
        let report = try await h.run([node])
        #expect(report.error(node) == "A network takes at most 2,000 curves.")
    }

    @Test func aKernelWithoutNetworkSurfacesSaysSo() async throws {
        var h = Harness()
        let node = h.add(NetworkSurfaceNode.self)
        let a = h.add(RectangleNode.self), b = h.add(RectangleNode.self)
        h.wire(a, "profile", to: node, "u curves")
        h.wire(b, "profile", to: node, "v curves")
        let report = try await h.run([node])
        #expect(report.error(node) == "Network surfaces isn't supported by this kernel yet.")
    }

    #if canImport(CreatorOCCT)
    @Test func aLineGridMakesASheetOfTheGridsArea() async throws {
        var h = Harness()
        let node = grid(&h)
        let kernel = OCCTKernel()
        let report = try await h.run([node], kernel: kernel)
        #expect(report.error(node) == nil)
        let sheet = try onlySolid(report, node, "surface")
        let area = try await kernel.properties(of: sheet).surfaceArea
        #expect(isClose(area, 100, relative: 1e-5))
    }
    #endif
}
