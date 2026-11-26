import CreatorGeometry
import CreatorKernel

/// What one solid gives a section view (R14): the part left on the viewer's side of the cutting line, and the cut faces to hatch.
public struct SectionCutPiece: Sendable {
    public var remainder: Solid?
    public var regions: [HatchRegion]
    /// Whether the section of a part that should be hatched failed (the part is drawn unhatched).
    public var hatchFailed: Bool

    public init(remainder: Solid?, regions: [HatchRegion] = [], hatchFailed: Bool = false) {
        self.remainder = remainder
        self.regions = regions
        self.hatchFailed = hatchFailed
    }

    var estimatedBytes: Int {
        let regionBytes = regions.reduce(0) { $0 + 64 + $1.edges.reduce(0) { $0 + 16 * $1.count } }
        return (remainder?.estimatedBytes ?? 0) + regionBytes + 64
    }
}

/// One solid's cut and its hatch regions (R1, R5).
enum SectionMaker {
    static func cut(
        _ solid: Solid, index: Int, cutter: SectionCutter, tolerance: Double, kernel: any Kernel
    ) async throws -> SectionCutPiece {
        let tag = NodeTag(node: SectionCutter.toolNode, item: index)
        let remainder = try await kernel.cutAway(solid, by: cutter, tag: tag)
        try Task.checkCancellation()
        // Sheets are never sectioned (R5): a value with an open shell and no closed solid has no hatch and no kernel call.
        guard solid.holdsClosedSolid else { return SectionCutPiece(remainder: remainder) }
        do {
            let regions = try await regions(of: solid, index: index, cutter: cutter, tolerance: tolerance, kernel: kernel)
            return SectionCutPiece(remainder: remainder, regions: regions)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return SectionCutPiece(remainder: remainder, hatchFailed: true)
        }
    }

    private static func regions(
        of solid: Solid, index: Int, cutter: SectionCutter, tolerance: Double, kernel: any Kernel
    ) async throws -> [HatchRegion] {
        let frame = SectionFrame.frame(for: cutter)
        let right = cutter.frame.right, up = cutter.frame.up
        let t = cutter.direction
        let viewing = right * cutter.viewing.x + up * cutter.viewing.y
        let along = right * t.x + up * t.y
        let bands = HatchBand.bands(for: cutter)
        var result: [HatchRegion] = []
        for (order, k) in cutter.cutIndices.enumerated() {
            let p = cutter.points[k]
            let plane = Plane(origin: right * p.x + up * p.y, normal: viewing, xAxis: along)
            let section = try await kernel.section(solid, by: plane, tolerance: tolerance)
            try Task.checkCancellation()
            for region in section.regions where isHatchable(region, in: solid) {
                let loops = loops(of: region.boundary.map { $0.polyline.map(frame.place) })
                guard !loops.isEmpty else { continue }
                result.append(HatchRegion(part: index, edges: loops, band: bands[order]))
            }
        }
        return result
    }

    /// A mixed value's region is hatched only when every piece of its boundary lies on a face of a closed solid (R5).
    private static func isHatchable(_ region: SectionRegion, in solid: Solid) -> Bool {
        guard solid.hasOpenShell else { return true }
        return region.boundary.allSatisfy { piece in
            guard let id = piece.sourceFace, let face = solid.topology.face(id) else { return false }
            return !face.isOnOpenShell
        }
    }

    /// Chains boundary pieces end to end into closed loops, in order; an unmatched piece starts a loop of its own.
    static func loops(of pieces: [[Vector2]]) -> [[Vector2]] {
        let epsilon = 1e-6
        var remaining = pieces.filter { $0.count >= 2 }
        var loops: [[Vector2]] = []
        func same(_ a: Vector2, _ b: Vector2) -> Bool { (a - b).length <= epsilon }
        while !remaining.isEmpty {
            var loop = remaining.removeFirst()
            while let last = loop.last, let first = loop.first, !same(last, first) || loop.count < 3 {
                guard let next = remaining.firstIndex(where: { same($0.first ?? .zero, last) || same($0.last ?? .zero, last) })
                else { break }
                var piece = remaining.remove(at: next)
                if !same(piece[0], last) { piece.reverse() }
                loop.append(contentsOf: piece.dropFirst())
            }
            if let first = loop.first, let last = loop.last, same(first, last) { loop.removeLast() }
            if loop.count >= 3 { loops.append(loop) }
        }
        return loops
    }
}
