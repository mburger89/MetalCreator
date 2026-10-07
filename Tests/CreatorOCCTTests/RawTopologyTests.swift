import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

struct RawTopologyTests {
    @Test func boxPropertiesAreAnalytic() throws {
        let properties = try OCCTShape.box(10, 20, 30).properties()
        #expect(isClose(properties.volume, 6000))
        #expect(isClose(properties.surfaceArea, 2 * (200 + 600 + 300)))
        #expect(isClose(properties.centroid.x, 5) && isClose(properties.centroid.y, 10) && isClose(properties.centroid.z, 15))
        #expect(isClose(properties.bounds.min.x, 0, relative: 1e-4) && isClose(properties.bounds.max.z, 30, relative: 1e-4))
    }

    @Test func boxFacesArePlanarWithOutwardNormals() throws {
        let topology = try OCCTRawTopology.read(OCCTShape.box(10, 20, 30))
        #expect(topology.faces.count == 6)
        #expect(topology.faces.allSatisfy { $0.kind == .plane })
        for face in topology.faces {
            let normal = try #require(face.normal)
            let outward = face.centroid - Vector3(5, 10, 15)
            #expect(normal.dot(outward) > 0, "normal \(normal) points inward for centroid \(face.centroid)")
            #expect(isClose(normal.length, 1))
        }
        #expect(isClose(topology.faces.map(\.area).reduce(0, +), 2200))
    }

    @Test func boxEdgesAreConvexLinesBetweenTwoFaces() throws {
        let topology = try OCCTRawTopology.read(OCCTShape.box(10, 20, 30))
        #expect(topology.edges.count == 12)
        #expect(topology.edges.allSatisfy { $0.kind == .line && $0.convexity == .convex })
        #expect(topology.edges.allSatisfy { $0.faces.count == 2 && $0.faces[0] != $0.faces[1] })
        #expect(topology.edges.filter { isClose($0.length, 30) }.count == 4)
        let vertical = topology.edges.filter { isClose($0.length, 30) }
        #expect(vertical.allSatisfy { abs(($0.direction ?? .zero).dot(.unitZ)) > 0.999 })
    }

    @Test func initializeIsIdempotent() {
        occtInitialize()
        occtInitialize()
    }
}
