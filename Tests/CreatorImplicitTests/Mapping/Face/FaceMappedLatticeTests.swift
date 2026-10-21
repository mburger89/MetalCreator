import CreatorGeometry
import Foundation
import Testing
@testable import CreatorImplicit

/// A lattice under the Face mapping of a cylinder's side (implicit spec §3.5): the lattice read at the face's coordinates, the cells
/// meeting where the angle wraps round, and the axis, where the map is singular, left solid.
struct FaceMappedLatticeTests {
    static let axis = LatticeFixtures.crossing
    static let huge = BoundingBox(min: Vector3(-1000, -1000, -1000), max: Vector3(1000, 1000, 1000))

    /// The face-mapped fixtures' lattices with a region that never cuts.
    func lattices(_ mapping: LatticeMapping) -> [(name: String, mapped: ImplicitSolid, straight: ImplicitSolid)] {
        let cells = LatticeFixtures.cells(8)
        let tpms = ImplicitSolid.tpms(TPMSLattice(type: .gyroid, form: .sheet, cells: cells, thickness: .constant(1.1), region: Self.huge,
                                                  mapping: mapping))
        let struts = ImplicitSolid.struts(StrutLattice(cell: .bcc, cells: cells, radius: .constant(0.7), blend: 0.2, region: Self.huge,
                                                       mapping: mapping))
        return [
            ("gyroid", tpms, LatticeFixtures.mapped(tpms, .straight)),
            ("bcc struts", struts, LatticeFixtures.mapped(struts, .straight)),
        ]
    }

    func around(_ axis: Vector3, count: Int, stream: Int) -> [Vector3] {
        let random = SeededRandom(seed: 11, stream: stream)
        return (0..<count).map { index in
            let (radius, angle) = (3 + 12 * random.unit(at: 3 * index), 2 * Double.pi * random.unit(at: 3 * index + 1))
            return Vector3(axis.x + radius * cos(angle), axis.y + radius * sin(angle), 20 * random.unit(at: 3 * index + 2) - 10)
        }
    }

    @Test func theFaceCoordinatesAreTheCylindricalOnesTurnedHalfWayRound() throws {
        let mapping = LatticeFixtures.face(cell: 8)
        guard case .face(let face) = mapping, let radius = face.firstRadius else { Issue.record("not a face map"); return }
        let cylinder = try #require(CylindricalMap(axis: Plane(origin: Self.axis, normal: .unitZ, xAxis: .unitX), radius: radius,
                                                   over: LatticeFixtures.region))
        for point in around(Self.axis, count: 300, stream: 1) {
            let (f, c) = (mapping.coordinates(at: point), cylinder.coordinates(at: point))
            // The face measures its angle from the middle of u (π, opposite +X), so the pattern is turned by half a turn.
            #expect(abs(cos(f.x / radius) + cos(c.x / radius)) < 0.03 && abs(sin(f.x / radius) + sin(c.x / radius)) < 0.03, "\(point)")
            #expect(abs(f.y - c.y) < 1e-3, "the height")
            // Within the chart's spacing: a distance is a cone about the axis, which a grid of 0.7 mm cuts a little short.
            #expect(abs(f.z - (c.z - 14)) < 0.06, "the depth is the distance from the axis less the radius: \(f.z) against \(c.z - 14)")
        }
    }

    @Test func aFaceMappedLatticeIsTheStraightLatticeAtTheFaceCoordinates() {
        let mapping = LatticeFixtures.face(cell: nil)
        for (kind, mapped, straight) in lattices(mapping) {
            var compared = 0
            for point in around(Self.axis, count: 300, stream: 2)
            where mapping.singularDistance(at: point) > LatticeMapping.exclusion + LatticeMapping.fadeWidth {
                let expected = straight.signedDistance(at: mapping.coordinates(at: point))
                #expect(abs(mapped.signedDistance(at: point) - expected) < 1e-9, "\(kind) at \(point)")
                compared += 1
            }
            #expect(compared > 250)
        }
    }

    @Test func theAxisOfTheCylinderIsLeftSolid() {
        let mapping = LatticeFixtures.face(cell: 8)
        for (kind, mapped, _) in lattices(mapping) {
            for z in stride(from: -9.0, through: 9.0, by: 1.5) {
                #expect(mapped.signedDistance(at: Vector3(Self.axis.x, Self.axis.y, z)) <= 1e-9, "\(kind): solid on the axis")
            }
        }
    }

    @Test func aWholeNumberOfCellsGoesRoundSoTheLatticeMeetsItselfWhereTheAngleWraps() {
        let mapping = LatticeFixtures.face(cell: 8)
        for (kind, mapped, _) in lattices(mapping) {
            // The wrap is where u passes 2π: the half-plane toward +X from the axis.
            for z in [-3.0, 0.4, 5.5] {
                for reach in [6.0, 9.0, 12.0] {
                    let (above, below) = (mapped.signedDistance(at: Vector3(Self.axis.x + reach, Self.axis.y + 1e-6, z)),
                                          mapped.signedDistance(at: Vector3(Self.axis.x + reach, Self.axis.y - 1e-6, z)))
                    #expect(abs(above - below) < 1e-4, "\(kind) at reach \(reach), z = \(z): \(above) against \(below)")
                }
            }
        }
    }

    @Test func theSeedsOfAVoronoiLatticeAreMappedAndCopiedAcrossTheWrap() {
        let mapping = LatticeFixtures.face(cell: nil)
        let region = LatticeFixtures.region
        let points = LatticeFixtures.seeds(36, seed: 3)
        let seeds = VoronoiSeeds.mapped(points: points, mapping: mapping, region: region)
        #expect(seeds.realCount == 36 && seeds.ghostCount > 0)
        #expect(seeds.points[0] == mapping.coordinates(at: points[0]))
        let uncovered = seeds.uncoveredFraction(in: region, mapping: mapping)
        #expect(uncovered < 0.5, "the seeds reach most of the mapped region: \(uncovered)")
    }

    @Test func theLipschitzBoundIncludesTheStretchAndTheBlend() {
        let plain = LatticeFixtures.tpmsAll[0].solid
        let wrapped = LatticeFixtures.faceAll[0].solid
        #expect(wrapped.lipschitz > plain.lipschitz * 2)
    }
}
