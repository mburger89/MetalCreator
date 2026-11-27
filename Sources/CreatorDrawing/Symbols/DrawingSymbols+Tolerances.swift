import CreatorGeometry

extension DrawingSymbols {
    /// tan 30 degrees: the run of a 60 degree line per unit of rise. An exact constant, never `sin` or `cos`.
    public static let slant = (3.0).squareRoot() / 3
    /// sin 60 degrees.
    public static let sixty = (3.0).squareRoot() / 2

    /// A characteristic's symbol in the box h by h whose bottom left is `origin` (plan R3). Every point is `origin + unit * h`.
    public static func characteristic(_ characteristic: GeometricCharacteristic, origin: Vector2, h: Double) -> [SheetSegment] {
        func point(_ x: Double, _ y: Double) -> Vector2 { Vector2(origin.x + x * h, origin.y + y * h) }
        func circle(_ x: Double, _ y: Double, _ radius: Double) -> SheetSegment {
            .arc(center: point(x, y), radius: radius * h, start: 0, sweep: 2 * .pi)
        }
        switch characteristic {
        case .straightness, .flatness, .circularity, .cylindricity, .lineProfile, .surfaceProfile:
            return formGlyph(characteristic, point: point, circle: circle, h: h)
        case .parallelism, .perpendicularity, .angularity, .position, .concentricity, .symmetry, .circularRunout, .totalRunout:
            return placedCharacteristic(characteristic, origin: origin, h: h)
        }
    }

    /// The form symbols (straightness to the profiles); every other characteristic is `placedCharacteristic`'s.
    private static func formGlyph(
        _ characteristic: GeometricCharacteristic, point: (Double, Double) -> Vector2, circle: (Double, Double, Double) -> SheetSegment,
        h: Double
    ) -> [SheetSegment] {
        let s = sixty
        switch characteristic {
        case .straightness:
            return [.line(point(0, 0.5), point(1, 0.5))]
        case .flatness:
            return [.polyline([point(0, 0.2), point(0.7, 0.2), point(1, 0.8), point(0.3, 0.8), point(0, 0.2)])]
        case .circularity:
            return [circle(0.5, 0.5, 0.5)]
        case .cylindricity:
            return [
                circle(0.5, 0.5, 0.3),
                .line(point(0.3 + 0.3 * s, 0.35 - 0.4 * s), point(0.7 + 0.3 * s, 0.35 + 0.4 * s)),
                .line(point(0.3 - 0.3 * s, 0.65 - 0.4 * s), point(0.7 - 0.3 * s, 0.65 + 0.4 * s)),
            ]
        case .lineProfile:
            return [.arc(center: point(0.5, 0.25), radius: 0.5 * h, start: 0, sweep: .pi)]
        case .surfaceProfile:
            return [.arc(center: point(0.5, 0.25), radius: 0.5 * h, start: 0, sweep: .pi), .line(point(0, 0.25), point(1, 0.25))]
        case .parallelism, .perpendicularity, .angularity, .position, .concentricity, .symmetry, .circularRunout, .totalRunout:
            return []
        }
    }

    /// The orientation, location and run-out symbols.
    private static func placedCharacteristic(_ characteristic: GeometricCharacteristic, origin: Vector2, h: Double) -> [SheetSegment] {
        func point(_ x: Double, _ y: Double) -> Vector2 { Vector2(origin.x + x * h, origin.y + y * h) }
        func circle(_ x: Double, _ y: Double, _ radius: Double) -> SheetSegment {
            .arc(center: point(x, y), radius: radius * h, start: 0, sweep: 2 * .pi)
        }
        let k = slant
        switch characteristic {
        case .parallelism:
            return [.line(point(0.1, 0), point(0.1 + k, 1)), .line(point(0.4, 0), point(0.4 + k, 1))]
        case .perpendicularity:
            return [.line(point(0.5, 0), point(0.5, 1)), .line(point(0, 0), point(1, 0))]
        case .angularity:
            return [.polyline([point(1, k), point(0, 0), point(1, 0)])]
        case .position:
            return [circle(0.5, 0.5, 0.35), .line(point(0, 0.5), point(1, 0.5)), .line(point(0.5, 0), point(0.5, 1))]
        case .concentricity:
            return [circle(0.5, 0.5, 0.5), circle(0.5, 0.5, 0.25)]
        case .symmetry:
            return [
                .line(point(0.15, 0.2), point(0.85, 0.2)), .line(point(0, 0.5), point(1, 0.5)),
                .line(point(0.15, 0.8), point(0.85, 0.8)),
            ]
        case .circularRunout:
            return [.line(point(0.1, 0.1), point(0.9, 0.9)), .polyline([point(0.6, 0.9), point(0.9, 0.9), point(0.9, 0.6)])]
        case .totalRunout:
            return [
                .line(point(0, 0.1), point(0.6, 0.7)), .line(point(0.4, 0.1), point(1, 0.7)), .line(point(0, 0.1), point(0.4, 0.1)),
                .polyline([point(0.35, 0.7), point(0.6, 0.7), point(0.6, 0.45)]),
                .polyline([point(0.75, 0.7), point(1, 0.7), point(1, 0.45)]),
            ]
        case .straightness, .flatness, .circularity, .cylindricity, .lineProfile, .surfaceProfile: return []
        }
    }

    /// A circled modifier: a full circle about `center` and the letter, centred on it (plan R3).
    public static func circled(
        _ letter: String, center: Vector2, h: Double, standard: DrawingStandard
    ) -> (segments: [SheetSegment], text: PlacedText) {
        let style = SymbolStyle.of(standard)
        let height = style.circledLetter * h
        let run = DrawingText.layout(letter, height: height)
        let text = PlacedText(
            run: run, original: letter, origin: Vector2(center.x - run.width / 2, center.y - height / 2), height: height, angle: 0)
        return ([.arc(center: center, radius: style.circleRadius * h, start: 0, sweep: 2 * .pi)], text)
    }

    /// The lay symbol perpendicular to the lines of a surface: the perpendicularity glyph at 0.8h.
    public static func layPerpendicular(origin: Vector2, h: Double, standard: DrawingStandard) -> [SheetSegment] {
        characteristic(.perpendicularity, origin: origin, h: SymbolStyle.of(standard).layGlyph * h)
    }
}
