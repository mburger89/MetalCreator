import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorOCCT
import Testing

struct ExtrudeRevolveNodeTests {
    @Test func boxVolumeIsExact() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let box = h.box(10, 20, 30)
        let report = try await h.run([box], kernel: kernel)
        let solid = try onlySolid(report, box)
        #expect(isClose(try await volume(solid, kernel), 6000))
        #expect(report.isOK(box))
    }

    @Test func symmetricAndReversedExtrudesMoveTheSolid() async throws {
        var h = Harness()
        let rectangle = h.add(RectangleNode.self)
        let symmetric = h.add(ExtrudeNode.self, ["distance": .number(30), "mode": .integer(1)])
        let reversed = h.add(ExtrudeNode.self, ["distance": .number(30), "reversed": .bool(true)])
        h.wire(rectangle, "profile", to: symmetric, "profile")
        h.wire(rectangle, "profile", to: reversed, "profile")
        let report = try await h.run([symmetric, reversed], kernel: OCCTKernel())
        let a = try onlySolid(report, symmetric).bounds
        let b = try onlySolid(report, reversed).bounds
        #expect(isClose(a.min.z, -15, relative: 1e-6) && isClose(a.max.z, 15, relative: 1e-6))
        #expect(isClose(b.min.z, -30, relative: 1e-6) && abs(b.max.z) < 1e-6)
    }

    @Test func roundedPlateVolumeAccountsForTheCorners() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let plate = h.add(RoundedRectangleNode.self)
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(6)])
        h.wire(plate, "profile", to: extrude, "profile")
        let solid = try onlySolid(try await h.run([extrude], kernel: kernel), extrude)
        #expect(isClose(try await volume(solid, kernel), (60 * 40 - (4 - Double.pi) * 16) * 6))
        #expect(solid.topology.faces.count == 10)
    }

    @Test func broadcastExtrudeTagsEachItem() async throws {
        var h = Harness()
        let grid = h.add(GridPointsNode.self)
        let circle = h.add(CircleNode.self, ["diameter": .number(5)])
        let extrude = h.add(ExtrudeNode.self, ["distance": .number(20), "mode": .integer(1)])
        h.wire(grid, "points", to: circle, "plane")
        h.wire(circle, "profile", to: extrude, "profile")
        let report = try await h.run([extrude], kernel: OCCTKernel())
        let solids = try #require(report.value(extrude, "solid")?.solids)
        #expect(solids.count == 4)
        for (item, solid) in solids.enumerated() {
            #expect(solid.topology.faces.allSatisfy { $0.tags.allSatisfy { $0.node == extrude.id && $0.item == item } })
        }
    }

    @Test func badDistancesAndOpenProfilesAreExplained() async throws {
        var h = Harness()
        let rectangle = h.add(RectangleNode.self)
        let zero = h.add(ExtrudeNode.self, ["distance": .number(0)])
        h.wire(rectangle, "profile", to: zero, "profile")
        let points = h.add(GridPointsNode.self, ["countX": .integer(3), "countY": .integer(1)])
        let open = h.add(PolylineNode.self, ["closed": .bool(false)])
        h.wire(points, "points", to: open, "points")
        let openExtrude = h.add(ExtrudeNode.self)
        h.wire(open, "profile", to: openExtrude, "profile")
        let unwired = h.add(ExtrudeNode.self)
        let report = try await h.run([zero, openExtrude, unwired], kernel: OCCTKernel())
        #expect(report.error(zero) == "Extrude distance must be greater than 0 mm.")
        #expect(report.error(openExtrude) == "The profile is not a closed loop.")
        #expect(report.state(unwired) == .idle("Connect or set “profile”."))
    }

    @Test func revolvingAnOffsetRectangleMakesATube() async throws {
        let kernel = OCCTKernel()
        var h = Harness()
        let plane = h.add(PlaneNode.self, ["orientation": .integer(1)])
        let rectangle = h.add(RectangleNode.self, ["width": .number(5), "height": .number(10), "anchor": .integer(6)])
        h.wire(plane, "plane", to: rectangle, "plane")
        let revolve = h.add(RevolveNode.self, ["axisOrigin": .vector(Vector3(-5, 0, 0))])
        h.wire(rectangle, "profile", to: revolve, "profile")
        let quarter = h.add(RevolveNode.self, ["axisOrigin": .vector(Vector3(-5, 0, 0)), "angle": .number(90)])
        h.wire(rectangle, "profile", to: quarter, "profile")
        let report = try await h.run([revolve, quarter], kernel: kernel)
        #expect(isClose(try await volume(try onlySolid(report, revolve), kernel), Double.pi * (100 - 25) * 10))
        #expect(isClose(try await volume(try onlySolid(report, quarter), kernel), Double.pi * (100 - 25) * 10 / 4))
    }

    @Test func kernelErrorsReachTheNodeInPlainWords() async throws {
        var h = Harness()
        let rectangle = h.add(RectangleNode.self)
        let revolve = h.add(RevolveNode.self)
        h.wire(rectangle, "profile", to: revolve, "profile")
        let report = try await h.run([revolve], kernel: FakeKernel())
        #expect(report.error(revolve) == "Revolve isn't supported by this kernel yet.")
    }
}
