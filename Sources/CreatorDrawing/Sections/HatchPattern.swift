import CreatorGeometry

/// Hatching (R5): thin 45-degree-family lines on `n . x = j x spacing` in sheet millimetres, so the regions of one part line up and
/// the phase never depends on where the view sits.
public enum HatchPattern {
    private static let half = (0.5).squareRoot()
    private static let halfRootThree = (3.0).squareRoot() / 2

    /// The part's line direction: 45, 135, 30, 120, 60, 150 degrees by its index, repeating, as exact constants.
    public static func direction(forPart part: Int) -> Vector2 {
        switch ((part % 6) + 6) % 6 {
        case 0: Vector2(half, half)
        case 1: Vector2(-half, half)
        case 2: Vector2(halfRootThree, 0.5)
        case 3: Vector2(-0.5, halfRootThree)
        case 4: Vector2(0.5, halfRootThree)
        default: Vector2(-halfRootThree, 0.5)
        }
    }

    /// The hatch of `regions`, in region order, then lines by j ascending, then pieces along each line.
    public static func strokes(
        _ regions: [HatchRegion], mapping: ViewMapping, clips: [HatchClip], spacing: Double, width: Double, view: ViewID
    ) -> [SheetStroke] {
        guard spacing > 0 else { return [] }
        var strokes: [SheetStroke] = []
        for region in regions {
            let frame = LineFrame(direction: direction(forPart: region.part))
            let loops = region.edges.map { $0.map(mapping.sheet) }.filter { $0.count >= 3 }
            let limits = Limits(region: region, mapping: mapping, clips: clips)
            // The extent across the lines of the piece that remains after the band and the clips (a region's band piece), so the
            // thin-piece fallback is decided on what is drawn, never on the whole cut face.
            guard let extent = limits.extent(of: loops, frame: frame) else { continue }
            let first = Int((extent.low / spacing).rounded(.up)), last = Int((extent.high / spacing).rounded(.down))
            func appendPieces(of loops: [[Vector2]], at offset: Double) {
                for piece in frame.pieces(of: loops, at: offset) {
                    guard let kept = limits.apply(to: piece, frame: frame, offset: offset) else { continue }
                    strokes.append(
                        SheetStroke(
                            segments: [.line(frame.point(offset, kept.lowerBound), frame.point(offset, kept.upperBound))],
                            width: width, pattern: .solid, layer: .hatch, view: view))
                }
            }
            let before = strokes.count
            if first <= last {
                for offset in (first...last).map({ Double($0) * spacing }) {
                    appendPieces(of: loops, at: offset)
                }
            }
            // A piece no line of the grid crosses (thinner than the spacing, or an extent that only touches a line) gets one line
            // through its middle.
            if strokes.count == before, extent.high > extent.low { appendPieces(of: loops, at: (extent.low + extent.high) / 2) }
        }
        return strokes
    }

    private static let minimumPiece = 1e-9

    /// The line family's frame: `d` along the lines, `n` across.
    struct LineFrame {
        let d: Vector2
        var n: Vector2 { Vector2(-d.y, d.x) }

        init(direction: Vector2) { d = direction }

        func across(_ p: Vector2) -> Double { n.x * p.x + n.y * p.y }
        func along(_ p: Vector2) -> Double { d.x * p.x + d.y * p.y }
        func point(_ offset: Double, _ t: Double) -> Vector2 { n * offset + d * t }

        /// The inside pieces of the line at `offset`, as intervals along it (even-odd over every loop's edges).
        func pieces(of loops: [[Vector2]], at offset: Double) -> [ClosedRange<Double>] {
            var crossings: [Double] = []
            for loop in loops {
                let s = loop.map(across)
                for i in loop.indices {
                    let j = (i + 1) % loop.count
                    guard (s[i] > offset) != (s[j] > offset) else { continue }
                    let u = (offset - s[i]) / (s[j] - s[i])
                    let a = along(loop[i]), b = along(loop[j])
                    crossings.append(a + (b - a) * u)
                }
            }
            crossings.sort()
            var result: [ClosedRange<Double>] = []
            var index = 0
            while index + 1 < crossings.count {
                if crossings[index + 1] - crossings[index] > HatchPattern.minimumPiece {
                    result.append(crossings[index]...crossings[index + 1])
                }
                index += 2
            }
            return result
        }
    }

    /// A region's band and the detail clips, in sheet millimetres.
    private struct Limits {
        let band: (axis: AlignmentAxis, low: Double?, high: Double?)?
        let clips: [(center: Vector2, radius: Double)]

        init(region: HatchRegion, mapping: ViewMapping, clips: [HatchClip]) {
            if let band = region.band {
                let axisOffset = band.axis == .horizontal ? mapping.offset.x : mapping.offset.y
                self.band = (band.axis, band.low.map { $0 * mapping.scale + axisOffset }, band.high.map { $0 * mapping.scale + axisOffset })
            } else {
                band = nil
            }
            self.clips = clips.map { (mapping.sheet($0.center), $0.radius * mapping.scale) }
        }

        /// The range of `frame.across` over the loops' vertices cut to the band, and to each clip circle's reach; `nil` when nothing
        /// of the region is left.
        func extent(of loops: [[Vector2]], frame: LineFrame) -> (low: Double, high: Double)? {
            var low = Double.infinity, high = -Double.infinity
            for loop in loops {
                var polygon = loop
                if let band {
                    let coordinate: (Vector2) -> Double = band.axis == .horizontal ? { $0.x } : { $0.y }
                    if let bound = band.low { polygon = Self.clipped(polygon, coordinate: coordinate, keepsAbove: true, at: bound) }
                    if let bound = band.high { polygon = Self.clipped(polygon, coordinate: coordinate, keepsAbove: false, at: bound) }
                }
                for point in polygon {
                    let value = frame.across(point)
                    low = min(low, value)
                    high = max(high, value)
                }
            }
            for clip in clips {
                let middle = frame.across(clip.center)
                low = max(low, middle - clip.radius)
                high = min(high, middle + clip.radius)
            }
            return low <= high ? (low, high) : nil
        }

        /// Sutherland-Hodgman against one half plane `coordinate >= bound` (or `<=`).
        private static func clipped(_ polygon: [Vector2], coordinate: (Vector2) -> Double, keepsAbove: Bool, at bound: Double)
            -> [Vector2] {
            func inside(_ p: Vector2) -> Bool { keepsAbove ? coordinate(p) >= bound : coordinate(p) <= bound }
            var result: [Vector2] = []
            for index in polygon.indices {
                let a = polygon[index], b = polygon[(index + 1) % polygon.count]
                if inside(a) { result.append(a) }
                if inside(a) != inside(b) {
                    let t = (bound - coordinate(a)) / (coordinate(b) - coordinate(a))
                    result.append(a + (b - a) * t)
                }
            }
            return result
        }

        func apply(to piece: ClosedRange<Double>, frame: LineFrame, offset: Double) -> ClosedRange<Double>? {
            var low = piece.lowerBound, high = piece.upperBound
            if let band {
                let origin = frame.n * offset
                let o = band.axis == .horizontal ? origin.x : origin.y
                let slope = band.axis == .horizontal ? frame.d.x : frame.d.y
                for (bound, isLow) in [(band.low, true), (band.high, false)] {
                    guard let bound else { continue }
                    if abs(slope) < 1e-12 {
                        if isLow ? o < bound : o > bound { return nil }
                        continue
                    }
                    let t = (bound - o) / slope
                    if (slope > 0) == isLow { low = max(low, t) } else { high = min(high, t) }
                }
            }
            for clip in clips {
                let height = frame.across(clip.center) - offset
                guard abs(height) <= clip.radius else { return nil }
                let reach = (clip.radius * clip.radius - height * height).squareRoot()
                let middle = frame.along(clip.center)
                low = max(low, middle - reach)
                high = min(high, middle + reach)
            }
            return high - low > HatchPattern.minimumPiece ? low...high : nil
        }
    }
}
