#if canImport(CreatorOCCT)
import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorKernel
@testable import CreatorOCCT

/// NS-4 Task 4: `Kernel.split(_:by:tag:)` and `Kernel.subSheet(_:of:)` (R2, R4, R6, R7).
struct SheetSplitTests {
    let source = NodeTag(node: NodeID(), item: 0)
    let cutterTag = NodeTag(node: NodeID(), item: 0)
    let splitTag = NodeTag(node: NodeID(), item: 0)

    func rectangle(_ kernel: OCCTKernel, x: ClosedRange<Double>, y: ClosedRange<Double>, z: Double = 0) async throws -> Curve {
        let corners = [Vector3(x.lowerBound, y.lowerBound, z), Vector3(x.upperBound, y.lowerBound, z),
                       Vector3(x.upperBound, y.upperBound, z), Vector3(x.lowerBound, y.upperBound, z),
        ]
        return try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: source)
    }

    func square(_ kernel: OCCTKernel, half: Double = 10) async throws -> Solid {
        try await kernel.planarSurface([try await rectangle(kernel, x: -half...half, y: -half...half)], tag: source)
    }

    func circle(_ kernel: OCCTKernel, radius: Double, at center: Vector3) async throws -> Curve {
        try await kernel.makeCurve([.arc(center: center, normal: .unitZ, radius: radius,
                                         start: center + Vector3(radius, 0, 0), sweep: 2 * .pi),
                                        ], tag: cutterTag)
    }

    func line(_ kernel: OCCTKernel, _ a: Vector3, _ b: Vector3) async throws -> Curve {
        try await kernel.makeCurve([.line(a, b)], tag: cutterTag)
    }

    func along(_ curves: [Curve], _ direction: Vector3 = .unitZ) -> TrimCutter {
        .curves(curves, projection: .alongDirection, direction: direction)
    }

    func area(_ split: SheetSplit, _ faces: Set<FaceID>) -> Double {
        split.whole.topology.faces.filter { faces.contains($0.id) }.reduce(0) { $0 + $1.area }
    }

    func refusal(_ body: () async throws -> Void) async -> String? {
        do { try await body() } catch KernelError.invalidInput(let text) { return text } catch { return "other: \(error)" }
        return nil
    }

    func disk(_ kernel: OCCTKernel, radius: Double = 5) async throws -> (sheet: Solid, split: SheetSplit) {
        let sheet = try await square(kernel)
        let cutter = try await circle(kernel, radius: radius, at: Vector3(0, 0, 5))
        return (sheet, try await kernel.split(sheet, by: along([cutter]), tag: splitTag))
    }

    @Test func aCircleCutsADisk() async throws {
        let kernel = OCCTKernel()
        let (_, split) = try await disk(kernel)
        #expect(split.whole.topology.faces.count == 2)
        #expect(split.pieces.count == 2)
        let inside = try #require(split.inside)
        #expect(inside.count == 1)
        let diskArea = area(split, inside)
        #expect(abs(diskArea - 25 * .pi) / (25 * .pi) < 1e-6)
        let all = Set(split.whole.topology.faces.map(\.id))
        let ring = area(split, all.subtracting(inside))
        #expect(abs(ring - (400 - 25 * .pi)) / 400 < 1e-6)
    }

    @Test func cutEdgesAreNamedByTheCutter() async throws {
        let kernel = OCCTKernel()
        let (_, split) = try await disk(kernel)
        let role = TopoTag(splitTag, .boundary(.cut(.curve(index: 0, piece: 0))))
        let cut = split.whole.topology.edges.filter { $0.tags.contains(role) }
        #expect(!cut.isEmpty)
        #expect(cut.allSatisfy { $0.faces.count == 2 })
    }

    @Test func piecesCarrySideTags() async throws {
        let kernel = OCCTKernel()
        let (sheet, split) = try await disk(kernel)
        let base = try #require(sheet.topology.faces.first).tags
        let name = CutterName.curve(index: 0, piece: 0)
        let inside = try #require(split.inside)
        let diskFace = try #require(split.whole.topology.faces.first { inside.contains($0.id) })
        let ringFace = try #require(split.whole.topology.faces.first { !inside.contains($0.id) })
        #expect(diskFace.tags == base.union([TopoTag(splitTag, .cutSide(name, .inside))]))
        #expect(ringFace.tags == base.union([TopoTag(splitTag, .cutSide(name, .outside))]))
    }

    @Test func inputEdgesKeepTheirTags() async throws {
        let kernel = OCCTKernel()
        let (_, split) = try await disk(kernel)
        for segment in 0..<4 {
            let role = TopoTag(source, .boundary(.piece(loop: 0, segment: segment)))
            #expect(split.whole.topology.edges.contains { $0.tags.contains(role) })
        }
    }

    @Test func aPickSurvivesTheCutterGrowing() async throws {
        let kernel = OCCTKernel()
        let (_, small) = try await disk(kernel, radius: 5)
        let (_, large) = try await disk(kernel, radius: 6)
        let diskID = try #require(small.inside?.first)
        let pick = try #require(small.whole.topology.facePick(for: diskID))
        let found = large.whole.topology.faces(matching: pick)
        #expect(found.count == 1)
        #expect(found.first?.id == large.inside?.first)
    }

    @Test func anOpenCurveCutsFrontAndBack() async throws {
        let kernel = OCCTKernel()
        let sheet = try await square(kernel)
        let cutter = try await line(kernel, Vector3(-20, 0, 5), Vector3(20, 0, 5))
        let split = try await kernel.split(sheet, by: along([cutter]), tag: splitTag)
        #expect(split.pieces.count == 2)
        #expect(split.inside == nil)
        let name = CutterName.curve(index: 0, piece: 0)
        let front = try #require(split.whole.topology.faces.first {
            $0.tags.contains(TopoTag(splitTag, .cutSide(name, .front)))
        })
        let back = try #require(split.whole.topology.faces.first {
            $0.tags.contains(TopoTag(splitTag, .cutSide(name, .back)))
        })
        #expect(front.centroid.y < 0)
        #expect(back.centroid.y > 0)
    }

    @Test func aSheetCutterCuts() async throws {
        let kernel = OCCTKernel()
        let sheet = try await square(kernel)
        let corners = [Vector3(3, -20, -20), Vector3(3, 20, -20), Vector3(3, 20, 20), Vector3(3, -20, 20)]
        let loop = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: cutterTag)
        let wall = try await kernel.planarSurface([loop], tag: cutterTag)
        let split = try await kernel.split(sheet, by: .body(wall), tag: splitTag)
        #expect(split.pieces.count == 2)
        #expect(split.inside == nil)
        let name = CutterName.face(try #require(wall.topology.faces.first).tags)
        let sides = split.whole.topology.faces.flatMap { face in
            [CutSide.front, .back].filter { face.tags.contains(TopoTag(splitTag, .cutSide(name, $0))) }
        }
        #expect(Set(sides) == [.front, .back])
        // R2: front is the side the cutter face's oriented normal points to.
        let wallFace = try #require(wall.topology.faces.first)
        let normal = try #require(wallFace.normal)
        let frontFace = try #require(split.whole.topology.faces.first {
            $0.tags.contains(TopoTag(splitTag, .cutSide(name, .front)))
        })
        let towardFront = frontFace.centroid.x - 3
        #expect(towardFront * normal.x > 0)
    }

    @Test func anOpenCurveAlongNormalsHasFrontAndBack() async throws {
        let kernel = OCCTKernel()
        let sections = try await [-10.0, 0, 10].enumerated().asyncMap { index, y in
            try await kernel.makeCurve([.line(Vector3(-10, y, index == 1 ? 3 : 0), Vector3(10, y, index == 1 ? 3 : 0))], tag: source)
        }
        let bump = try await kernel.loftSurface(sections, ruled: false, closed: false, tag: source)
        let cutter = try await line(kernel, Vector3(0, -20, 10), Vector3(0, 20, 10))
        let split = try await kernel.split(bump, by: .curves([cutter], projection: .alongNormals, direction: .unitZ), tag: splitTag)
        #expect(split.pieces.count == 2)
        let name = CutterName.curve(index: 0, piece: 0)
        let front = try #require(split.whole.topology.faces.first { $0.tags.contains(TopoTag(splitTag, .cutSide(name, .front))) })
        let back = try #require(split.whole.topology.faces.first { $0.tags.contains(TopoTag(splitTag, .cutSide(name, .back))) })
        // R2: front is t x N. The curve runs along +y; the loft's normal at the top of the bump is +z (u along x, v along y), so
        // front is the +x side.
        #expect(front.centroid.x > 0)
        #expect(back.centroid.x < 0)
    }

    @Test func aClosedSolidCutterGivesInside() async throws {
        let kernel = OCCTKernel()
        let sheet = try await square(kernel)
        let part = try await kernel.extrude(.rectangle(width: 4, height: 4, plane: .xy), distance: 4, mode: .symmetric, tag: cutterTag)
        let split = try await kernel.split(sheet, by: .body(part), tag: splitTag)
        let inside = try #require(split.inside)
        #expect(abs(area(split, inside) - 16) < 1e-6)
    }

    @Test func alongNormalsOnACurvedSheet() async throws {
        let kernel = OCCTKernel()
        let sections = try await [-10.0, 0, 10].enumerated().asyncMap { index, y in
            try await kernel.makeCurve([.line(Vector3(-10, y, index == 1 ? 3 : 0), Vector3(10, y, index == 1 ? 3 : 0))], tag: source)
        }
        let bump = try await kernel.loftSurface(sections, ruled: false, closed: false, tag: source)
        let cutter = try await circle(kernel, radius: 3, at: Vector3(0, 0, 10))
        let split = try await kernel.split(bump, by: .curves([cutter], projection: .alongNormals, direction: .unitZ), tag: splitTag)
        #expect(split.pieces.count == 2)
        #expect(split.inside != nil)
    }

    @Test func aHoledProfileCutsAnAnnulusInside() async throws {
        let kernel = OCCTKernel()
        let sheet = try await square(kernel, half: 10)
        let outer = try await circle(kernel, radius: 6, at: Vector3(0, 0, 5))
        let hole = try await circle(kernel, radius: 3, at: Vector3(0, 0, 5))
        let split = try await kernel.split(sheet, by: along([outer, hole]), tag: splitTag)
        let inside = try #require(split.inside)
        #expect(abs(area(split, inside) - 27 * .pi) / (27 * .pi) < 1e-6)
    }

    @Test func aDanglingCurveWarns() async throws {
        let kernel = OCCTKernel()
        let sheet = try await square(kernel)
        let ring = try await circle(kernel, radius: 5, at: Vector3(0, 0, 5))
        let spur = try await line(kernel, Vector3(0, 0, 5), Vector3(30, 0, 5))
        let split = try await kernel.split(sheet, by: along([ring, spur]), tag: splitTag)
        #expect(split.pieces.count == 2)
        #expect(split.warnings.contains("Part of the cutter doesn't cross the surface from edge to edge, so it cut nothing there."))
        let message = await refusal { _ = try await kernel.split(sheet, by: along([spur]), tag: splitTag) }
        #expect(message == "The cutter doesn't cut the surface.")
    }

    @Test func aMissingCutterRefuses() async throws {
        let kernel = OCCTKernel()
        let sheet = try await square(kernel)
        let away = try await circle(kernel, radius: 5, at: Vector3(100, 100, 5))
        let message = await refusal { _ = try await kernel.split(sheet, by: along([away]), tag: splitTag) }
        #expect(message == "The cutter doesn't cut the surface.")
    }

    @Test func aDistantCurveStillCuts() async throws {
        let kernel = OCCTKernel()
        let sheet = try await square(kernel)
        let reference = try await disk(kernel).split
        let referenceArea = area(reference, try #require(reference.inside))
        for z in [100.0, -250] {
            let split = try await kernel.split(sheet, by: along([try await circle(kernel, radius: 5, at: Vector3(0, 0, z))]),
                                               tag: splitTag)
            #expect(split.pieces.count == 2)
            #expect(abs(area(split, try #require(split.inside)) - referenceArea) < 1e-6)
        }
        let down = try await kernel.split(sheet, by: along([try await circle(kernel, radius: 5, at: Vector3(0, 0, 5))], Vector3(0, 0, -1)),
                                          tag: splitTag)
        #expect(abs(area(down, try #require(down.inside)) - referenceArea) < 1e-6)
    }

    @Test func aBandCutLeavesTwoOutsidePiecesWithOneName() async throws {
        let kernel = OCCTKernel()
        let strip = try await kernel.planarSurface([try await rectangle(kernel, x: -10...10, y: -3...3)], tag: source)
        let cutter = try await circle(kernel, radius: 5, at: Vector3(0, 0, 5))
        let split = try await kernel.split(strip, by: along([cutter]), tag: splitTag)
        #expect(split.pieces.count == 3)
        let outside = TopoTag(splitTag, .cutSide(.curve(index: 0, piece: 0), .outside))
        let pieces = split.pieces.filter { ids in
            ids.allSatisfy { split.whole.topology.faces[$0.rawValue].tags.contains(outside) }
        }
        #expect(pieces.count == 2)
        let tagSets = pieces.map { split.whole.topology.faces[$0[0].rawValue].tags }
        #expect(tagSets[0] == tagSets[1])
        let xs = pieces.map { split.whole.topology.faces[$0[0].rawValue].centroid.x }
        #expect(xs[0] < 0 && xs[1] > 0)
    }
}

/// The rest of NS-4 Task 4's split tests: refusals, pieces, `subSheet`, a periodic sheet and cancellation.
struct SheetSplitPieceTests {
    let helper = SheetSplitTests()
    var source: NodeTag { helper.source }
    var cutterTag: NodeTag { helper.cutterTag }
    var splitTag: NodeTag { helper.splitTag }
    func square(_ kernel: OCCTKernel, half: Double = 10) async throws -> Solid { try await helper.square(kernel, half: half) }
    func rectangle(_ kernel: OCCTKernel, x: ClosedRange<Double>, y: ClosedRange<Double>) async throws -> Curve {
        try await helper.rectangle(kernel, x: x, y: y)
    }
    func circle(_ kernel: OCCTKernel, radius: Double, at center: Vector3) async throws -> Curve {
        try await helper.circle(kernel, radius: radius, at: center)
    }
    func line(_ kernel: OCCTKernel, _ a: Vector3, _ b: Vector3) async throws -> Curve { try await helper.line(kernel, a, b) }
    func along(_ curves: [Curve]) -> TrimCutter { helper.along(curves) }
    func disk(_ kernel: OCCTKernel) async throws -> (sheet: Solid, split: SheetSplit) { try await helper.disk(kernel) }
    func refusal(_ body: () async throws -> Void) async -> String? { await helper.refusal(body) }

    @Test func aClosedSolidIsRefused() async throws {
        let kernel = OCCTKernel()
        let part = try await box(kernel, 10, 10, 10)
        let cutter = try await circle(kernel, radius: 2, at: Vector3(0, 0, 5))
        let message = await refusal { _ = try await kernel.split(part, by: along([cutter]), tag: splitTag) }
        #expect(message == "Trim and Split take a sheet; this is a closed solid.")
    }

    @Test func piecesAreConnectedSets() async throws {
        let kernel = OCCTKernel()
        let sections = try await [0.0, 10, 20].asyncMap { y in
            try await kernel.makeCurve([.line(Vector3(-10, y, 0), Vector3(10, y, y / 5))], tag: source)
        }
        let ruled = try await kernel.loftSurface(sections, ruled: true, closed: false, tag: source)
        #expect(ruled.topology.faces.count == 2)
        let corners = [Vector3(0, -5, -20), Vector3(0, 30, -20), Vector3(0, 30, 20), Vector3(0, -5, 20)]
        let loop = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: cutterTag)
        let wall = try await kernel.planarSurface([loop], tag: cutterTag)
        let split = try await kernel.split(ruled, by: .body(wall), tag: splitTag)
        #expect(split.pieces.count == 2)
        #expect(split.pieces.allSatisfy { $0.count == 2 })
        let keys = split.pieces.map { ids in
            ids.map { split.whole.topology.faces[$0.rawValue].tags.map(\.sortKey).sorted().joined(separator: "+") }.min() ?? ""
        }
        #expect(keys[0] < keys[1])
    }

    /// A sheet of two loose faces, as Import Model makes: a STEP file of two separate squares.
    func looseSheet(_ kernel: OCCTKernel) async throws -> Solid {
        let a = try await kernel.shape(of: try await helper.square(kernel, half: 5))
        let far = try await helper.rectangle(kernel, x: 20...30, y: 0...10)
        let b = try await kernel.shape(of: try await kernel.planarSurface([far], tag: source))
        let directory = URL.temporaryDirectory.appending(path: "loose-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "model")
        try OCCTKernel.serialized { () throws in
            try OCCTShape.compound([a, b]).writeSTEP(to: url, unit: "MM")
        }
        let read = try await kernel.readShapes(try Data(contentsOf: url), format: .step, tag: source)
        return try #require(read.sheets.first)
    }

    @Test func aSheetOfLooseFacesSplits() async throws {
        let kernel = OCCTKernel()
        let sheet = try await looseSheet(kernel)
        #expect(sheet.topology.faces.count == 2)
        let cutter = try await circle(kernel, radius: 2, at: Vector3(0, 0, 5))
        let split = try await kernel.split(sheet, by: along([cutter]), tag: splitTag)
        #expect(split.whole.topology.faces.count == 3)
        #expect(split.pieces.count == 3)
        #expect(split.inside != nil)
    }

    @Test func subSheetOfDisjointPiecesIsValid() async throws {
        let kernel = OCCTKernel()
        let strip = try await kernel.planarSurface([try await rectangle(kernel, x: -10...10, y: -3...3)], tag: source)
        let cutter = try await circle(kernel, radius: 5, at: Vector3(0, 0, 5))
        let split = try await kernel.split(strip, by: along([cutter]), tag: splitTag)
        let outside = TopoTag(splitTag, .cutSide(.curve(index: 0, piece: 0), .outside))
        let ids = split.whole.topology.faces.filter { $0.tags.contains(outside) }.map(\.id)
        #expect(ids.count == 2)
        let sub = try await kernel.subSheet(ids, of: split.whole)
        #expect(sub.topology.faces.count == 2)
        #expect(try await kernel.shape(of: sub).isValid)
    }

    @Test func subSheetCarriesNames() async throws {
        let kernel = OCCTKernel()
        let (_, split) = try await disk(kernel)
        let diskID = try #require(split.inside?.first)
        let sub = try await kernel.subSheet([diskID], of: split.whole)
        #expect(sub.topology.faces.count == 1)
        #expect(sub.topology.faces[0].tags == split.whole.topology.faces[diskID.rawValue].tags)
        let cut = sub.topology.edges.filter { $0.tags.contains { $0.role == .boundary(.cut(.curve(index: 0, piece: 0))) } }
        #expect(!cut.isEmpty)
        #expect(cut.allSatisfy { $0.isBoundary && sub.topology.key(of: $0) != nil })
        let everything = try await kernel.subSheet(split.whole.topology.faces.map(\.id), of: split.whole)
        let shared = everything.topology.edges.filter { $0.tags.contains { $0.role == .boundary(.cut(.curve(index: 0, piece: 0))) } }
        #expect(!shared.isEmpty)
        #expect(shared.allSatisfy { $0.faces.count == 2 })
    }

    @Test func aPeriodicSheetSplitsAcrossItsSeam() async throws {
        let kernel = OCCTKernel()
        let wall = try await line(kernel, Vector3(10, 0, 0), Vector3(10, 0, 20))
        let axis = Axis(origin: .zero, direction: .unitZ)
        let cylinder = try await kernel.revolve(wall, axis: axis, angle: Angle(radians: 2 * .pi), tag: source)
        let corners = [Vector3(-20, -20, 10), Vector3(20, -20, 10), Vector3(20, 20, 10), Vector3(-20, 20, 10)]
        let loop = try await kernel.makeCurve(corners.indices.map { .line(corners[$0], corners[($0 + 1) % 4]) }, tag: cutterTag)
        let cutter = try await kernel.planarSurface([loop], tag: cutterTag)
        let split = try await kernel.split(cylinder, by: .body(cutter), tag: splitTag)
        #expect(split.pieces.count == 2)
        let a = try await kernel.subSheet(split.pieces[0], of: split.whole)
        let b = try await kernel.subSheet(split.pieces[1], of: split.whole)
        let cut = try #require(a.topology.edges.first { $0.tags.contains { if case .boundary(.cut) = $0.role { true } else { false } } })
        let found = try await kernel.continuity(of: cut.id, in: a, against: FaceID(0), of: b)
        #expect(found.grade == .g2)
    }

    @Test func cancellationStops() async throws {
        let kernel = OCCTKernel()
        let sheet = try await square(kernel)
        let cutter = try await circle(kernel, radius: 5, at: Vector3(0, 0, 5))
        let task = Task { try await kernel.split(sheet, by: along([cutter]), tag: splitTag) }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("a cancelled split finished")
        } catch is CancellationError {
        } catch {
            Issue.record("expected cancellation, got \(error)")
        }
    }
}

private extension Sequence {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var out: [T] = []
        for element in self { out.append(try await transform(element)) }
        return out
    }
}
#endif
