import CreatorGeometry
import Foundation

/// Variable-radius Poisson-disk sampling of a flat region (fields spec §3.3), Bridson's method: "Fast Poisson Disk Sampling
/// in Arbitrary Dimensions" (SIGGRAPH 2007), with the radius taken from a field at each candidate.
///
/// A seed is a draw inside the region's box that the region allows and that is clear of the points placed so far. Then, in
/// rounds, every active point makes `candidatesPerPoint` candidates in the annulus from its own spacing `r` to `2r` (uniform by
/// area); the candidates the region refuses, or that are closer than `minSpacing` to a placed point, are dropped without asking
/// the field; the spacing of all that remain is asked for in one batch (the field is sampled once per round, never once per
/// candidate); and then each active point, in order, takes its first candidate that is at least that candidate's spacing from
/// every placed point, those taken earlier in the round included. A point that took one stays active with a fresh set of
/// draws, one that took none is retired. When none is active a new seed is drawn, which fills islands the margin cut off and
/// the parts of the region the annuli cannot reach across a jump in the spacing; the search ends when `seedingTries` seed draws
/// in a row find no room.
///
/// Every draw is `SeededRandom(seed:stream:purpose: .scatter)`: stream 0 for seeds, parent index + 1 for a parent's
/// candidates, the draw index counting that stream's draws. A draw depends on the seed and the place alone, never on how the
/// candidates were batched, so the same inputs give the same points on the same platform (libm `cos` and `sin` may differ in the last bit across architectures or OS versions). A spacing is at least `minSpacing`, so
/// no two points are ever closer than that.
struct PoissonScatter: Sendable {
    /// Candidates tried round an active point before it is retired.
    static let candidatesPerPoint = 30
    /// Seed draws in a row that may find no room before the search ends.
    static let seedingTries = 1_024
    /// Seed draws spaced by one call to the field.
    static let seedBatch = 64

    let region: FaceRegion
    let margin: Double
    let minSpacing: Double
    let maxSpacing: Double
    let seed: Int
    /// The search stops once more than this many points exist, so a node can say how many it would have placed.
    let ceiling: Int

    struct Outcome: Equatable, Sendable {
        var points: [Vector2]
        /// True when the search stopped at the ceiling: there would have been more than `points.count - 1` points.
        var reachedCeiling: Bool
    }

    /// The points, in the order they were placed. `spacing` is given a batch of points of the region and returns the spacing at
    /// each, in the same order (at least `minSpacing` and at most `maxSpacing`).
    func scatter(spacing: ([Vector2]) async throws -> [Double]) async throws -> Outcome {
        try Task.checkCancellation()
        guard let box = region.bounds, minSpacing > 0, maxSpacing >= minSpacing else {
            return Outcome(points: [], reachedCeiling: false)
        }
        var placed = Placed(origin: box.min, width: max(minSpacing, maxSpacing / 16))
        var seedDraws = 0
        var active: [Active] = []
        while placed.points.count <= ceiling {
            try Task.checkCancellation()
            if active.isEmpty {
                guard let seed = try await nextSeed(in: box, placed: placed, draws: &seedDraws, spacing: spacing) else { break }
                placed.add(seed.point, radius: seed.radius)
                active = [Active(index: placed.points.count - 1, attempt: 0)]
                continue
            }
            let options = active.map { candidates(of: $0, placed: placed) }
            let flat = options.flatMap { $0 }
            let radii = flat.isEmpty ? [] : try await spacing(flat)
            precondition(radii.count == flat.count, "the spacing closure must return one value per point")
            var kept: [Active] = []
            var children: [Active] = []
            var next = 0
            for (parent, choices) in zip(active, options) {
                var tookOne = false
                for (offset, point) in choices.enumerated() where placed.isClear(point, within: radii[next + offset]) {
                    placed.add(point, radius: radii[next + offset])
                    children.append(Active(index: placed.points.count - 1, attempt: 0))
                    tookOne = true
                    break
                }
                next += choices.count
                if tookOne { kept.append(Active(index: parent.index, attempt: parent.attempt + Self.candidatesPerPoint)) }
                if placed.points.count > ceiling { break }
            }
            active = kept + children
        }
        return Outcome(points: placed.points, reachedCeiling: placed.points.count > ceiling)
    }

    /// The next seed and its spacing: the first of the next `seedingTries` stream-0 draws that the region allows, that is not
    /// closer than `minSpacing` to a placed point and not closer than its own spacing to any. The field is asked in batches of
    /// `seedBatch` draws. `draws` counts every seed draw made so far, so no draw is ever used twice. `nil` when none has room.
    private func nextSeed(in box: (min: Vector2, max: Vector2), placed: Placed, draws: inout Int,
                          spacing: ([Vector2]) async throws -> [Double]) async throws -> (point: Vector2, radius: Double)? {
        let random = SeededRandom(seed: seed, stream: 0, purpose: .scatter)
        var tried = 0
        while tried < Self.seedingTries {
            try Task.checkCancellation()
            let batch = (0..<Self.seedBatch).compactMap { offset -> Vector2? in
                let draw = 2 * (draws + offset)
                let point = Vector2(box.min.x + (box.max.x - box.min.x) * random.unit(at: draw),
                                    box.min.y + (box.max.y - box.min.y) * random.unit(at: draw + 1))
                return region.allows(point, margin: margin) && placed.isClear(point, within: minSpacing) ? point : nil
            }
            draws += Self.seedBatch
            tried += Self.seedBatch
            guard !batch.isEmpty else { continue }
            let radii = try await spacing(batch)
            precondition(radii.count == batch.count, "the spacing closure must return one value per point")
            if let found = zip(batch, radii).first(where: { placed.isClear($0, within: $1) }) {
                return (found.0, found.1)
            }
        }
        return nil
    }

    /// The candidates round `parent` that the region allows and that are not closer than `minSpacing` to a placed point.
    private func candidates(of parent: Active, placed: Placed) -> [Vector2] {
        let random = SeededRandom(seed: seed, stream: parent.index + 1, purpose: .scatter)
        let centre = placed.points[parent.index]
        let radius = placed.radii[parent.index]
        return (0..<Self.candidatesPerPoint).compactMap { offset in
            let draw = 2 * (parent.attempt + offset)
            let distance = radius * (1 + 3 * random.unit(at: draw)).squareRoot()
            let angle = 2 * Double.pi * random.unit(at: draw + 1)
            let point = Vector2(centre.x + distance * cos(angle), centre.y + distance * sin(angle))
            guard region.allows(point, margin: margin), placed.isClear(point, within: minSpacing) else { return nil }
            return point
        }
    }

    /// A placed point that can still take candidates, and how many draws it has used.
    private struct Active {
        var index: Int
        var attempt: Int
    }

    private struct Cell: Hashable {
        var x: Int
        var y: Int
    }

    /// The points placed so far and a grid of them, `width` wide, for neighbour tests.
    private struct Placed {
        let origin: Vector2
        let width: Double
        private(set) var points: [Vector2] = []
        private(set) var radii: [Double] = []
        private var cells: [Cell: [Int]] = [:]

        init(origin: Vector2, width: Double) {
            self.origin = origin
            self.width = width
        }

        mutating func add(_ point: Vector2, radius: Double) {
            cells[cell(of: point), default: []].append(points.count)
            points.append(point)
            radii.append(radius)
        }

        /// True when no placed point is closer to `point` than `distance`.
        func isClear(_ point: Vector2, within distance: Double) -> Bool {
            let reach = Self.index((distance / width).rounded(.up))
            let centre = cell(of: point)
            for dx in -reach...reach {
                for dy in -reach...reach {
                    guard let neighbours = cells[Cell(x: centre.x + dx, y: centre.y + dy)] else { continue }
                    if neighbours.contains(where: { (points[$0] - point).length < distance }) { return false }
                }
            }
            return true
        }

        private func cell(of point: Vector2) -> Cell {
            Cell(x: Self.index((point.x - origin.x) / width), y: Self.index((point.y - origin.y) / width))
        }

        /// A grid index, held far inside `Int`'s range so a tiny spacing can't trap.
        private static func index(_ value: Double) -> Int {
            Int(Swift.max(Swift.min(value.rounded(.down), 1e15), -1e15))
        }
    }
}
