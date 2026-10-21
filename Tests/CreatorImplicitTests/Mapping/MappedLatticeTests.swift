import CreatorGeometry
import Testing
@testable import CreatorImplicit

/// A mapped lattice is the lattice read at the mapped coordinates (implicit spec §3.5), with the singular set left solid, and its
/// seeds are put through the same mapping.
struct MappedLatticeTests {
    /// A region so big that the cut to its box is never what a value is.
    static let huge = BoundingBox(min: Vector3(-1000, -1000, -1000), max: Vector3(1000, 1000, 1000))

    static let centre = Vector3(2, -3, 0)
    static let mappings: [(name: String, mapping: LatticeMapping)] = [
        ("cylindrical", LatticeFixtures.cylinder(through: centre, cell: nil)),
        ("spherical", LatticeFixtures.sphere(at: centre, cell: nil)),
    ]

    static var points: [Vector3] {
        ImplicitSolidPropertyTests.points(in: BoundingBox(min: Vector3(-30, -30, -20), max: Vector3(30, 30, 20)), count: 400, stream: 8)
    }

    func lattices(_ mapping: LatticeMapping) -> [(name: String, mapped: ImplicitSolid, straight: ImplicitSolid)] {
        let cells = LatticeFixtures.cells(7)
        let tpms = ImplicitSolid.tpms(TPMSLattice(type: .gyroid, form: .sheet, cells: cells, thickness: .constant(1.1), region: Self.huge,
                                                  mapping: mapping))
        let struts = ImplicitSolid.struts(StrutLattice(cell: .bcc, cells: cells, radius: .constant(0.7), blend: 0.2, region: Self.huge,
                                                       mapping: mapping))
        return [
            ("gyroid", tpms, LatticeFixtures.mapped(tpms, .straight)),
            ("bcc struts", struts, LatticeFixtures.mapped(struts, .straight)),
        ]
    }

    @Test(arguments: MappedLatticeTests.mappings.map(\.name))
    func aMappedLatticeIsTheStraightLatticeAtTheMappedCoordinates(_ name: String) throws {
        let mapping = try #require(Self.mappings.first { $0.name == name }?.mapping)
        for (kind, mapped, straight) in lattices(mapping) {
            var compared = 0
            for point in Self.points where mapping.singularDistance(at: point) > LatticeMapping.exclusion + LatticeMapping.fadeWidth {
                let expected = straight.signedDistance(at: mapping.coordinates(at: point))
                #expect(abs(mapped.signedDistance(at: point) - expected) < 1e-9, "\(kind) at \(point)")
                compared += 1
            }
            #expect(compared > 300)
        }
    }

    @Test(arguments: MappedLatticeTests.mappings.map(\.name))
    func theSingularSetIsLeftSolid(_ name: String) throws {
        let mapping = try #require(Self.mappings.first { $0.name == name }?.mapping)
        for (kind, mapped, _) in lattices(mapping) {
            // Along the singular set (x, y at the axis; z across the lattice) and just inside the exclusion of it.
            for z in stride(from: -15.0, through: 15.0, by: 1.3) {
                for offset in [0.0, 0.4, 0.99] {
                    let point = Vector3(Self.centre.x + offset, Self.centre.y, z)
                    #expect(mapped.signedDistance(at: point) <= 1e-9, "\(kind): solid within the exclusion")
                }
            }
        }
    }

    @Test func aWholeNumberOfCellsGoesRoundSoTheLatticeMeetsItselfAtTheCut() {
        let cell = 7.0
        let radius = LatticeMapping.turnRadius(mean: 9, cell: cell)
        guard let map = CylindricalMap(axis: .xy, radius: radius, over: Self.huge) else { Issue.record("no map"); return }
        let mapping = LatticeMapping.cylindrical(map)
        for (kind, mapped, _) in lattices(mapping) {
            for z in [-3.0, 0.4, 5.5] {
                for x in [-6.0, -11.0, -25.0] {
                    let (above, below) = (mapped.signedDistance(at: Vector3(x, 1e-7, z)), mapped.signedDistance(at: Vector3(x, -1e-7, z)))
                    #expect(abs(above - below) < 1e-5, "\(kind) at x = \(x), z = \(z): \(above) against \(below)")
                }
            }
        }
    }

    @Test func theSeedsAreMappedAndCopiedAcrossTheCut() throws {
        let region = BoundingBox(min: Vector3(-20, -20, -10), max: Vector3(20, 20, 10))
        let map = try #require(CylindricalMap(axis: .xy, radius: 10, over: region))
        let mapping = LatticeMapping.cylindrical(map)
        // One seed just above the cut (angle near π) and one at the far side of the circle.
        let points = [Vector3(-9, 1, 0), Vector3(9, 0, 0), Vector3(0, 8, 2)]
        let seeds = VoronoiSeeds.mapped(points: points, mapping: mapping, region: region)
        #expect(seeds.realCount == 3 && seeds.ghostCount >= 1 && seeds.points.count == 3 + seeds.ghostCount)
        #expect(seeds.points[0] == mapping.coordinates(at: points[0]))
        let period = 2 * Double.pi * 10
        let wanted = seeds.points[0] - Vector3(period, 0, 0)
        #expect(seeds.points.dropFirst(3).contains { ($0 - wanted).length < 1e-9 }, "the seed beside the cut has a copy a period away")
        #expect(seeds.points.dropFirst(3).allSatisfy { abs($0.x) > period / 2 - 1e-9 }, "copies sit beyond the cut")
        // Straight keeps the points as they are and no copies.
        let plain = VoronoiSeeds.mapped(points: points, mapping: .straight, region: region)
        #expect(plain.points == points && plain.ghostCount == 0 && plain.realCount == 3)
    }

    @Test func theCoordinateBoundsContainTheMappedRegion() throws {
        let region = BoundingBox(min: Vector3(5, -20, -10), max: Vector3(25, 20, 10))
        let mapping = LatticeFixtures.cylinder(through: .zero, cell: nil)
        let box = mapping.coordinateBounds(of: region)
        for point in ImplicitSolidPropertyTests.points(in: region, count: 500, stream: 3) {
            let m = mapping.coordinates(at: point)
            #expect(m.x >= box.min.x && m.x <= box.max.x && m.y >= box.min.y && m.y <= box.max.y && m.z >= box.min.z && m.z <= box.max.z)
        }
        #expect(LatticeMapping.straight.coordinateBounds(of: region) == region)
    }

    @Test func aMappedLatticeSaysSoInItsRecipe() {
        let mapping = LatticeFixtures.cylinder(through: .zero, cell: 8)
        #expect(LatticeFixtures.mapped(LatticeFixtures.tpmsAll[0].solid, mapping).description.hasSuffix(", cylindrical)"))
        #expect(LatticeFixtures.mapped(LatticeFixtures.strutsAll[0].solid, LatticeFixtures.sphere(at: .zero, cell: 6)).description
            .hasSuffix(", spherical)"))
        #expect(!LatticeFixtures.tpmsAll[0].solid.description.contains("cylindrical"))
        #expect(LatticeFixtures.mappedAll.last?.solid.description.contains("spherical") == true)
    }
}
