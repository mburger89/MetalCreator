import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

struct SelectionNodeTests {
    func edges(_ report: EvaluationReport, _ node: Node) throws -> EdgeSet {
        try #require(report.value(node, "edges")?.edgeSets?.first, "no edges: \(String(describing: report.state(node)))")
    }

    /// A 10 × 20 × 30 box with a Ø4 through hole along Z.
    func drilledBox(_ h: inout Harness) -> Node {
        let box = h.box(10, 20, 30)
        let circle = h.add(CircleNode.self, ["diameter": .number(4)])
        let hole = h.add(ExtrudeNode.self, ["distance": .number(80), "mode": .integer(1)])
        h.wire(circle, "profile", to: hole, "profile")
        let cut = h.add(BooleanNode.self, ["operation": .integer(1)])
        h.wire(box, "solid", to: cut, "target")
        h.wire(hole, "solid", to: cut, "tools")
        return cut
    }

    @Test func allEdgesSkipsSeams() async throws {
        var h = Harness()
        let cut = drilledBox(&h)
        let all = h.add(AllEdgesNode.self)
        h.wire(cut, "solid", to: all, "solid")
        let set = try edges(try await h.run([all], kernel: OCCTKernel()), all)
        #expect(set.edges.count == 14)
        #expect(set.edges.allSatisfy { set.solid.topology.edge($0)?.isSeam == false })
    }

    @Test func edgesParallelToZIgnoreHoleRimsAndSeams() async throws {
        var h = Harness()
        let cut = drilledBox(&h)
        let up = h.add(EdgesByDirectionNode.self)
        let down = h.add(EdgesByDirectionNode.self, ["direction": .vector(-.unitZ)])
        h.wire(cut, "solid", to: up, "solid")
        h.wire(cut, "solid", to: down, "solid")
        let report = try await h.run([up, down], kernel: OCCTKernel())
        let set = try edges(report, up)
        #expect(set.edges.count == 4)
        #expect(set.edges.allSatisfy { set.solid.topology.edge($0)?.kind == .line })
        #expect(try edges(report, down).edges == set.edges)
        #expect(report.isOK(up))
    }

    @Test func toleranceWidensTheMatch() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let tilted = h.add(TransformNode.self, ["angle": .number(3), "axisDirection": .vector(.unitX)])
        h.wire(box, "solid", to: tilted, "solid")
        let strict = h.add(EdgesByDirectionNode.self)
        let loose = h.add(EdgesByDirectionNode.self, ["tolerance": .number(5)])
        h.wire(tilted, "solid", to: strict, "solid")
        h.wire(tilted, "solid", to: loose, "solid")
        let report = try await h.run([strict, loose], kernel: OCCTKernel())
        #expect(try edges(report, strict).edges.isEmpty)
        #expect(report.warning(strict) == "This rule matched no edges.")
        #expect(try edges(report, loose).edges.count == 4)
    }

    @Test func aZeroDirectionIsExplained() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let rule = h.add(EdgesByDirectionNode.self, ["direction": .vector(.zero)])
        h.wire(box, "solid", to: rule, "solid")
        #expect(try await h.run([rule]).error(rule) == "The direction can't be zero.")
    }

    @Test func filterByConvexityAndLength() async throws {
        var h = Harness()
        let low = h.box(20, 10, 5)
        let high = h.box(10, 10, 10, at: Vector3(5, 0, 0))
        let step = h.add(BooleanNode.self)
        h.wire(low, "solid", to: step, "target")
        h.wire(high, "solid", to: step, "tools")
        let concave = h.add(EdgeFilterNode.self, ["convexity": .integer(2)])
        let convex = h.add(EdgeFilterNode.self, ["convexity": .integer(1)])
        let long = h.add(EdgeFilterNode.self, ["minLength": .number(19.5), "maxLength": .number(20.5)])
        for rule in [concave, convex, long] { h.wire(step, "solid", to: rule, "solid") }
        let report = try await h.run([concave, convex, long], kernel: OCCTKernel())
        let inner = try edges(report, concave)
        #expect(inner.edges.count == 1)
        #expect(inner.edges.allSatisfy { inner.solid.topology.edge($0)?.convexity == .concave })
        #expect(try edges(report, convex).edges.count == inner.solid.topology.edges.count - 1)
        #expect(try edges(report, long).edges.count == 2)
    }

    @Test func aReversedLengthRangeIsExplained() async throws {
        var h = Harness()
        let box = h.box(10, 10, 10)
        let rule = h.add(EdgeFilterNode.self, ["minLength": .number(5), "maxLength": .number(2)])
        h.wire(box, "solid", to: rule, "solid")
        #expect(try await h.run([rule]).error(rule) == "“minLength” (5 mm) is more than “maxLength” (2 mm).")
    }

    @Test func setOpsDedupeAndKeepOrder() async throws {
        var h = Harness()
        let box = h.box(10, 20, 30)
        let vertical = h.add(EdgesByDirectionNode.self)
        let long = h.add(EdgeFilterNode.self, ["minLength": .number(25)])
        let all = h.add(AllEdgesNode.self)
        for rule in [vertical, long, all] { h.wire(box, "solid", to: rule, "solid") }
        func op(_ index: Int, _ a: Node, _ b: Node) -> Node {
            let node = h.add(EdgeSetOpNode.self, ["operation": .integer(index)])
            h.wire(a, "edges", to: node, "a")
            h.wire(b, "edges", to: node, "b")
            return node
        }
        let union = op(0, vertical, long)
        let subtract = op(1, all, vertical)
        let intersect = op(2, all, vertical)
        let empty = op(1, vertical, long)
        let report = try await h.run([union, subtract, intersect, empty], kernel: OCCTKernel())
        let verticalEdges = try edges(report, vertical).edges
        #expect(try edges(report, union).edges == verticalEdges)
        #expect(try edges(report, subtract).edges.count == 8)
        #expect(Set(try edges(report, intersect).edges) == Set(verticalEdges))
        #expect(report.warning(empty) == "This rule matched no edges.")
    }

    @Test func setsFromDifferentSolidsAreRefused() async throws {
        var h = Harness()
        let a = h.box(10, 10, 10)
        let b = h.box(10, 10, 10)
        let ruleA = h.add(AllEdgesNode.self)
        let ruleB = h.add(AllEdgesNode.self)
        h.wire(a, "solid", to: ruleA, "solid")
        h.wire(b, "solid", to: ruleB, "solid")
        let union = h.add(EdgeSetOpNode.self)
        h.wire(ruleA, "edges", to: union, "a")
        h.wire(ruleB, "edges", to: union, "b")
        #expect(try await h.run([union]).error(union) == "Both edge sets must select edges of the same solid. Wire both rules from the same node.")
    }
}
