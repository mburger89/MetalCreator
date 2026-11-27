#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// Hidden-line projection in OpenCascade (drawings DR-1, R9 and R10).
struct ProjectionTests {
    let tag = NodeTag(node: NodeID(), item: 0)
    let kernel = OCCTKernel()

    static let front = ProjectionFrame(direction: Vector3(0, 1, 0), up: Vector3(0, 0, 1))
    static let top = ProjectionFrame(direction: Vector3(0, 0, -1), up: Vector3(0, 1, 0))
    static let right = ProjectionFrame(direction: Vector3(-1, 0, 0), up: Vector3(0, 0, 1))
    static let isometric: ProjectionFrame = {
        let s = 1 / 3.0.squareRoot()
        return ProjectionFrame.make(direction: Vector3(-s, s, -s), up: Vector3(0, 0, 1))!
    }()

    @Test func spikeSourcesMapToTheInputsEdges() async throws {
        let solid = try await cornerBox()
        let projection = try await kernel.projection(of: solid, curves: [], frame: Self.front, options: ProjectionOptions())
        #expect(projection.lines.allSatisfy { $0.source != nil })
        let visible = lines(projection, .visible)
        let frontEdges = try faceEdges(solid, normal: Vector3(0, -1, 0))
        #expect(edgeIDs(visible) == frontEdges)
        for id in frontEdges {
            let covered = visible.filter { $0.source == .edge(id) }.reduce(0) { $0 + length($1.curve) }
            let edge = try #require(solid.topology.edge(id))
            #expect(abs(covered - edge.length) < 1e-9)
        }
        let backEdges = try faceEdges(solid, normal: Vector3(0, 1, 0))
        #expect(edgeIDs(lines(projection, .hidden)).isSubset(of: backEdges))
    }

    @Test func aBoxFromTheFrontIsTrueSize() async throws {
        let solid = try await cornerBox()
        let projection = try await kernel.projection(of: solid, curves: [], frame: Self.front, options: ProjectionOptions())
        let bounds = try #require(union(lines(projection, .visible).map(\.curve.bounds)))
        #expect(abs(bounds.min.x) < 1e-9 && abs(bounds.max.x - 10) < 1e-9)
        #expect(abs(bounds.min.y) < 1e-9 && abs(bounds.max.y - 30) < 1e-9)
    }

    @Test func anIsometricBoxShowsNineVisibleEdges() async throws {
        let solid = try await cornerBox()
        let projection = try await kernel.projection(of: solid, curves: [], frame: Self.isometric, options: ProjectionOptions())
        let visible = edgeIDs(lines(projection, .visible))
        let hidden = edgeIDs(lines(projection, .hidden))
        #expect(visible.count == 9)
        #expect(hidden.count == 3)
        #expect(visible.isDisjoint(with: hidden))
        #expect(projection.lines.allSatisfy { $0.lineClass == .sharp })
        #expect(projection.lines.allSatisfy { if case .line = $0.curve { true } else { false } })
    }

    @Test func aCylinderSideOnHasTwoOutlines() async throws {
        let solid = try await cylinder()
        let projection = try await kernel.projection(of: solid, curves: [], frame: Self.front, options: ProjectionOptions())
        let outlines = lines(projection, .visible, .outline)
        let sideFace = try #require(solid.topology.faces.first { $0.kind == .cylinder }).id
        #expect(!outlines.isEmpty)
        #expect(outlines.allSatisfy { $0.source == .face(sideFace) })
        for x in [-5.0, 5.0] {
            let side = outlines.filter { abs($0.curve.bounds.min.x - x) < 1e-6 && abs($0.curve.bounds.max.x - x) < 1e-6 }
            #expect(!side.isEmpty)
            let low = side.map(\.curve.bounds.min.y).min() ?? 1
            let high = side.map(\.curve.bounds.max.y).max() ?? 0
            #expect(abs(low) < 1e-6 && abs(high - 20) < 1e-6)
            #expect(abs(side.reduce(0) { $0 + length($1.curve) } - 20) < 1e-6)
        }
        #expect(outlines.count == outlines.filter { line in [-5.0, 5.0].contains { abs(line.curve.bounds.min.x - $0) < 1e-6 } }.count)
        #expect(projection.lines.allSatisfy { $0.source != nil })
        for edge in solid.topology.edges where edge.kind == .circle {
            let mine = lines(projection, .visible).filter { $0.source == .edge(edge.id) }
            #expect(!mine.isEmpty)
            let low = mine.map(\.curve.bounds.min.x).min() ?? 1
            let high = mine.map(\.curve.bounds.max.x).max() ?? -1
            #expect(abs(low + 5) < 1e-6 && abs(high - 5) < 1e-6)
        }
        let seams = Set(solid.topology.edges.filter(\.isSeam).map(\.id))
        #expect(edgeIDs(projection.lines).isDisjoint(with: seams))
    }

    @Test func aCylinderEndOnIsACircle() async throws {
        let solid = try await cylinder()
        let projection = try await kernel.projection(of: solid, curves: [], frame: Self.top, options: ProjectionOptions())
        let topEdge = try #require(solid.topology.edges.filter { $0.kind == .circle }.max { $0.midpoint.z < $1.midpoint.z })
        let arcs = lines(projection, .visible).filter { $0.source == .edge(topEdge.id) }
        #expect(!arcs.isEmpty)
        var sweep = 0.0
        for line in arcs {
            guard case .arc(_, let radius, _, let s) = line.curve else {
                Issue.record("expected an arc")
                continue
            }
            #expect(abs(radius - 5) < 1e-9)
            sweep += abs(s)
        }
        #expect(abs(sweep - 2 * .pi) < 1e-9)
    }

    @Test func aTiltedCircleIsAnExactEllipse() async throws {
        let solid = try await cylinder()
        let projection = try await kernel.projection(of: solid, curves: [], frame: Self.isometric, options: ProjectionOptions())
        let ellipses = projection.lines.filter { if case .ellipse = $0.curve { true } else { false } }
        #expect(!ellipses.isEmpty)
        for line in ellipses {
            guard case .ellipse(_, _, let major, let minor, _, _) = line.curve else { continue }
            #expect(abs(major - 5) < 1e-9)
            #expect(abs(minor - 5 / 3.0.squareRoot()) < 1e-9)
        }
        let topEdge = try #require(solid.topology.edges.filter { $0.kind == .circle }.max { $0.midpoint.z < $1.midpoint.z })
        #expect(ellipses.contains { $0.source == .edge(topEdge.id) })
    }

    @Test func aSplineEdgeIsAPolylineWithinTolerance() async throws {
        let sections = [(0.0, 5.0), (10.0, 8.0), (20.0, 5.0)].map {
            Profile2D.circle(radius: $0.1, center: .zero, plane: Plane.xy.offset(by: $0.0))
        }
        let loft = try await kernel.loft(sections, ruled: false, part: nil, start: nil, end: nil, tag: tag)
        let coarse = try await kernel.projection(of: loft, curves: [], frame: Self.front, options: ProjectionOptions(tolerance: 0.01))
        let fine = try await kernel.projection(of: loft, curves: [], frame: Self.front, options: ProjectionOptions(tolerance: 1e-4))
        func polylines(_ projection: Projection2D) -> [[Vector2]] {
            projection.lines.filter { $0.lineClass == .outline && $0.visibility == .visible }.compactMap {
                if case .polyline(let points) = $0.curve { points } else { nil }
            }
        }
        let coarseLines = polylines(coarse)
        let fineLines = polylines(fine)
        #expect(!coarseLines.isEmpty && !fineLines.isEmpty)
        func distance(_ p: Vector2, _ a: Vector2, _ b: Vector2) -> Double {
            let ab = b - a
            let t = max(0, min(1, ab.length < 1e-12 ? 0 : ((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / (ab.x * ab.x + ab.y * ab.y)))
            return (p - (a + ab * t)).length
        }
        for point in fineLines.joined() {
            let best = coarseLines.map { line in
                zip(line, line.dropFirst()).map { distance(point, $0.0, $0.1) }.min() ?? .infinity
            }.min() ?? .infinity
            #expect(best < 0.01 + 1e-6)
        }
        #expect(fineLines.joined().count > coarseLines.joined().count)
    }

    @Test func tangentEdgesAreSmooth() async throws {
        let solid = try await cornerBox()
        let corner = try #require(solid.topology.edges.first {
            $0.kind == .line && abs(($0.direction ?? .zero).dot(.unitZ)) > 0.999
                && abs($0.midpoint.x - 10) < 1e-6 && abs($0.midpoint.y) < 1e-6
        })
        let filleted = try await kernel.fillet(solid, edges: [corner.id], radius: 2, profile: .circular, tag: tag).solid
        let projection = try await kernel.projection(of: filleted, curves: [], frame: Self.front, options: ProjectionOptions())
        let smooth = lines(projection, .visible, .smooth)
        let blend = try #require(filleted.topology.faces.first { $0.kind == .cylinder }).id
        let tangentEdges = Set(filleted.topology.edges.filter { $0.faces.contains(blend) && !$0.isSeam && $0.kind == .line }.map(\.id))
        #expect(tangentEdges.count == 2)
        // Seen face-on, the round's tangent edge on the right-hand face is the silhouette and draws as an outline
        // (`aTangentEdgeOnTheSilhouetteIsAnOutline`); only the one on the face the viewer looks at is a tangent edge.
        let onSilhouette = Set(filleted.topology.edges.filter { tangentEdges.contains($0.id) && abs($0.midpoint.x - 10) < 1e-6 }.map(\.id))
        #expect(onSilhouette.count == 1)
        #expect(edgeIDs(smooth) == tangentEdges.subtracting(onSilhouette))
    }

    @Test func aSheetsEdgesAreSheetBoundaries() async throws {
        let corners = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 10, 0), Vector3(0, 10, 0)]
        let outline = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: tag)
        let sheet = try await kernel.planarSurface([outline], tag: tag)
        let projection = try await kernel.projection(of: sheet, curves: [], frame: Self.top, options: ProjectionOptions())
        let visible = lines(projection, .visible)
        #expect(visible.count == 4)
        #expect(visible.allSatisfy { $0.lineClass == .sheetBoundary })
    }

    @Test func curvesAreHiddenBehindTheSolid() async throws {
        let solid = try await cornerBox()
        let near = try await kernel.makeCurve([.line(Vector3(2, -10, 15), Vector3(8, -10, 15))], tag: tag)
        let inFront = try await kernel.projection(of: solid, curves: [near], frame: Self.front, options: ProjectionOptions())
        let curveLines = inFront.lines.filter { $0.lineClass == .curve }
        #expect(curveLines.count == 1)
        #expect(curveLines[0].visibility == .visible)
        #expect(curveLines[0].source == .curve(index: 0, piece: 0))

        let far = try await kernel.makeCurve([.line(Vector3(-5, 40, 15), Vector3(15, 40, 15))], tag: tag)
        let behind = try await kernel.projection(of: solid, curves: [far], frame: Self.front, options: ProjectionOptions())
        let hidden = behind.lines.filter { $0.lineClass == .curve && $0.visibility == .hidden }
        let shown = behind.lines.filter { $0.lineClass == .curve && $0.visibility == .visible }
        let hiddenBounds = try #require(union(hidden.map(\.curve.bounds)))
        #expect(abs(hiddenBounds.min.x) < 1e-6 && abs(hiddenBounds.max.x - 10) < 1e-6)
        #expect(!shown.isEmpty)
    }

    @Test func aLaterPieceOfACurveNamesItsPiece() async throws {
        let solid = try await cornerBox()
        let polyline = try await kernel.makeCurve(
            [.line(Vector3(2, -10, 15), Vector3(8, -10, 15)), .line(Vector3(8, -10, 15), Vector3(8, -10, 25))], tag: tag)
        let projection = try await kernel.projection(of: solid, curves: [polyline], frame: Self.front, options: ProjectionOptions())
        let sources = projection.lines.filter { $0.lineClass == .curve }.map(\.source)
        #expect(sources.contains(.curve(index: 0, piece: 0)))
        #expect(sources.contains(.curve(index: 0, piece: 1)))
    }

    @Test func severalSolidsHideEachOther() async throws {
        let near = try await cornerBox()
        let far = try await cornerBox(origin: Vector3(5, 40, 10), tag: NodeTag(node: NodeID(), item: 1))
        let both = try await kernel.compound([near, far], tag: tag)
        let projection = try await kernel.projection(of: both, curves: [], frame: Self.front, options: ProjectionOptions())
        let farEdges = Set(both.topology.edges.filter { $0.midpoint.y > 30 }.map(\.id))
        let covered = projection.lines.filter { line in
            if case .edge(let id)? = line.source { farEdges.contains(id) && line.visibility == .hidden } else { false }
        }
        #expect(!covered.isEmpty)
        // The far box's left front edge (x = 5, z 10 to 40) is covered up to z = 30 and clear above it.
        let leftEdge = try #require(both.topology.edges.first {
            farEdges.contains($0.id) && abs(($0.direction ?? .zero).dot(.unitZ)) > 0.999
                && abs($0.midpoint.x - 5) < 1e-6 && abs($0.midpoint.y - 40) < 1e-6
        })
        let onEdge = projection.lines.filter { $0.source == .edge(leftEdge.id) }
        #expect(onEdge.contains { $0.visibility == .hidden })
        #expect(onEdge.contains { $0.visibility == .visible })
    }

    @Test func noSolidAndNoCurvesIsEmpty() async throws {
        let projection = try await kernel.projection(of: nil, curves: [], frame: Self.front, options: ProjectionOptions())
        #expect(projection.lines.isEmpty)
    }

    @Test func aZeroDirectionIsRefused() async throws {
        let solid = try await cornerBox()
        await #expect(throws: KernelError.invalidInput("The view direction and its up direction must be perpendicular unit vectors.")) {
            try await kernel.projection(of: solid, curves: [], frame: ProjectionFrame(direction: .zero, up: .unitZ),
                                        options: ProjectionOptions())
        }
    }

    @Test func cancellationStops() async throws {
        let solid = try await cornerBox()
        let kernel = self.kernel
        // The task cancels itself before the call, so the outcome never depends on how fast the projection runs.
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await kernel.projection(of: solid, curves: [], frame: Self.front, options: ProjectionOptions())
        }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func aCancelledFlagStopsTheShimInItsWords() async throws {
        let solid = try await cornerBox()
        let source = try #require((solid.storage as? OCCTSolidStorage)?.shape)
        let flag = OCCTCancelFlag()
        flag.cancel()
        #expect {
            try OCCTKernel.serialized {
                try OCCTShape.projecting(source, curves: [], frame: Self.front, tolerance: 0.01, cancel: flag)
            }
        } throws: { ($0 as? OCCTError)?.message == OCCTCancelFlag.message }
    }

    @Test func theBracketsFourViewsProject() async throws {
        let bracket = try await BracketFixture.chamfered(kernel)
        let views: [(String, ProjectionFrame)] = [
            ("Front", Self.front), ("Right", Self.right), ("Top", Self.top), ("Isometric", Self.isometric),
        ]
        for (name, frame) in views {
            let started = ContinuousClock.now
            let projection = try await kernel.projection(of: bracket, curves: [], frame: frame, options: ProjectionOptions())
            let elapsed = started.duration(to: .now)
            let milliseconds = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
            #expect(!projection.lines.isEmpty)
            for line in projection.lines {
                switch line.source {
                case .edge(let id)?: #expect(bracket.topology.edges.indices.contains(id.rawValue))
                case .face(let id)?: #expect(bracket.topology.faces.indices.contains(id.rawValue))
                default: Issue.record("a line without a source")
                }
            }
            print("PROJECTION bracket \(name) \(projection.lines.count) \(Int(milliseconds.rounded()))")
        }
    }
}
#endif
