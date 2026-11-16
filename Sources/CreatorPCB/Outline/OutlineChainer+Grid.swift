import CreatorGeometry

extension OutlineChainer {
    struct Cell: Hashable {
        let x: Int, y: Int
    }

    /// Unused piece ends by grid cell (cell size = tolerance), so a nearest end is a 3 by 3 lookup.
    struct EndGrid {
        let pieces: [Piece]
        let size: Double
        var cells: [Cell: [Int]] = [:]
        var used: [Bool]
        /// How many end distances `nearest` has measured (tests prove the grid is used by bounding it).
        var evaluations = 0

        init(_ pieces: [Piece], tolerance: Double) {
            self.pieces = pieces
            size = max(tolerance, 1e-9)
            used = [Bool](repeating: false, count: pieces.count)
            for (index, piece) in pieces.enumerated() {
                cells[cell(piece.start), default: []].append(index * 2)
                cells[cell(piece.end), default: []].append(index * 2 + 1)
            }
        }

        func cell(_ point: Vector2) -> Cell {
            Cell(x: Int((point.x / size).rounded()), y: Int((point.y / size).rounded()))
        }

        /// The nearest unused end within the tolerance; ties within 1e-12 go to the lowest key, then identity, then index.
        mutating func nearest(to point: Vector2, tolerance: Double) -> (index: Int, flipped: Bool, distance: Double)? {
            let centre = cell(point)
            var best: (index: Int, flipped: Bool, distance: Double)?
            for dx in -1...1 {
                for dy in -1...1 {
                    for entry in cells[Cell(x: centre.x + dx, y: centre.y + dy)] ?? [] {
                        let index = entry / 2, flipped = entry % 2 == 1
                        guard !used[index] else { continue }
                        let end = flipped ? pieces[index].end : pieces[index].start
                        evaluations += 1
                        let distance = (end - point).length
                        guard distance <= tolerance else { continue }
                        if let current = best {
                            if distance < current.distance - 1e-12 {
                                best = (index, flipped, distance)
                            } else if abs(distance - current.distance) <= 1e-12, precedes(index, current.index) {
                                best = (index, flipped, distance)
                            } else if abs(distance - current.distance) <= 1e-12, index == current.index, !flipped {
                                best = (index, flipped, distance)
                            }
                        } else {
                            best = (index, flipped, distance)
                        }
                    }
                }
            }
            return best
        }

        func precedes(_ a: Int, _ b: Int) -> Bool {
            let (p, q) = (pieces[a], pieces[b])
            if p.key != q.key { return p.key < q.key }
            if p.identity != q.identity { return p.identity < q.identity }
            return a < b
        }
    }
}
