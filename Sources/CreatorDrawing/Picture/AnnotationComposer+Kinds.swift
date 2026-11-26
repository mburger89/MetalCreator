import CreatorGeometry
import CreatorKernel

/// An annotation that still holds: the labels it draws and the values it remembers.
struct HeldAnnotation {
    var labels: [DimensionLabel]
    var current: LastGood
    /// The first value's plain text.
    var label: String
    /// A symbol's line's projected ends, in the model plane (plan R5's extension line); empty for any other kind.
    var edgeEnds: [Vector2] = []
}

/// What resolving and measuring an annotation found: each anchor's state and the held result or the reason it is lost.
struct EvaluatedAnnotation {
    var anchors: [AnchorStatus]
    var outcome: Result<HeldAnnotation, LostReason>
}

/// Resolves, measures and labels an annotation (plan R4 to R6, R10, R12, R15). The composer and the refresh share it, so a
/// refreshed value is the one a compose would show.
enum AnnotationEvaluator {
    /// `nil` for a note, whose leaders are resolved by the composer alone.
    static func evaluate(
        _ annotation: DrawingAnnotation, topology: Topology, frame: ProjectionFrame, format: NumberFormat, parts: [PartSpan]
    ) -> EvaluatedAnnotation? {
        switch annotation.kind {
        case .dimension(let dimension): dimensionResult(dimension, topology: topology, frame: frame, format: format, parts: parts)
        case .holeCallout(let callout): hole(callout, topology: topology, frame: frame, format: format, parts: parts)
        case .centreMark(let mark): centreMark(mark, topology: topology, frame: frame, parts: parts)
        case .centreLine(let line): centreLine(line, topology: topology, frame: frame, parts: parts)
        case .note: nil
        case .balloon, .partsList, .revisionTable: nil  // their own passes compose them (a balloon's last value: `composeBalloon`)
        case .datumFeature, .featureControl, .surfaceTexture:
            symbol(annotation, topology: topology, frame: frame, format: format, parts: parts)
        }
    }

    /// A measure-level reason leaves every anchor held (plan R15); the others name the anchor.
    private static func status(of reason: LostReason) -> AnchorStatus { reason == .foreshortened ? .held : .lost(reason) }

    private static func lost(_ reason: LostReason, anchors: [AnchorStatus]) -> EvaluatedAnnotation {
        EvaluatedAnnotation(anchors: anchors, outcome: .failure(reason))
    }

    private static func held(
        _ anchors: [AnchorStatus], labels: [DimensionLabel], values: [Double], figure: AnnotationFigure, label: DimensionLabel?
    ) -> EvaluatedAnnotation {
        let lines = labels.flatMap { $0.plainText.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) }
        let first = label?.plainText.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return EvaluatedAnnotation(
            anchors: anchors,
            outcome: .success(
                HeldAnnotation(
                    labels: labels, current: LastGood(values: values, lines: lines, figure: figure), label: first)))
    }

    // MARK: Dimensions

    private static func dimensionResult(
        _ dimension: DrawingDimension, topology: Topology, frame: ProjectionFrame, format: NumberFormat, parts: [PartSpan]
    ) -> EvaluatedAnnotation {
        let resolutions = dimension.anchors.map { DrawingAnchorResolver.resolve($0, in: topology, frame: frame, parts: parts) }
        var anchors: [AnchorStatus] = []
        var firstLost: LostReason?
        for resolution in resolutions {
            if case .lost(let reason) = resolution {
                firstLost = firstLost ?? reason
                anchors.append(status(of: reason))
            } else {
                anchors.append(.held)
            }
        }
        if let firstLost { return lost(firstLost, anchors: anchors) }
        let measurement: DrawingMeasurement
        switch DrawingMeasure.measure(dimension, anchors: resolutions, frame: frame, mapping: nil) {
        case .failure(let reason): return lost(reason, anchors: anchors)
        case .success(let found): measurement = found
        }
        guard measurement.values.allSatisfy(\.isFinite) else { return lost(.refused(nonFiniteSentence), anchors: anchors) }
        do {
            let labels = try labels(of: dimension, values: measurement.values, format: format)
            return held(
                anchors, labels: labels, values: measurement.values, figure: measurement.figure, label: shownLabel(of: dimension, labels))
        } catch {
            return lost(.refused(error.sentence), anchors: anchors)
        }
    }

    /// The label a report names: an ordinate's origin "0" is no value.
    static func shownLabel(of dimension: DrawingDimension, _ labels: [DimensionLabel]) -> DimensionLabel? {
        if case .ordinate = dimension.kind, labels.count > 1 { return labels[1] }
        return labels.first
    }

    static let nonFiniteSentence = "What it measures has no finite size here."

    /// The labels a dimension shows for `values`: a held measurement's, and what a lost dimension remembers.
    static func labels(
        of dimension: DrawingDimension, values: [Double], format: NumberFormat
    ) throws(DrawingRefusal) -> [DimensionLabel] {
        func size(_ mm: Double, _ symbol: SizeSymbol) throws(DrawingRefusal) -> DimensionLabel {
            try DimensionLabel.size(
                mm, symbol: symbol, tolerance: dimension.tolerance, precision: dimension.precision, prefix: dimension.prefix,
                suffix: dimension.suffix, format: format)
        }
        func sizes(_ symbol: SizeSymbol) throws(DrawingRefusal) -> [DimensionLabel] {
            var result: [DimensionLabel] = []
            for value in values { result.append(try size(value, symbol)) }
            return result
        }
        switch dimension.kind {
        case .linear, .baseline, .chain: return try sizes(.none)
        case .radius: return try sizes(.radius)
        case .diameter: return try sizes(.diameter)
        case .ordinate:
            return [DimensionLabel.ordinate(0, precision: dimension.precision, format: format)]
                + values.map { DimensionLabel.ordinate($0, precision: dimension.precision, format: format) }
        case .angle:
            guard let value = values.first else { return [] }
            return [
                try DimensionLabel.angle(
                    value, tolerance: dimension.tolerance, precision: dimension.precision, prefix: dimension.prefix,
                    suffix: dimension.suffix, format: format),
            ]
        case .chamfer:
            guard values.count >= 2 else { return [] }
            return [DimensionLabel.chamfer(leg: values[0], angle: values[1], precision: dimension.precision, format: format)]
        }
    }

    // MARK: Hole callouts

    private static func hole(
        _ callout: HoleCallout, topology: Topology, frame: ProjectionFrame, format: NumberFormat, parts: [PartSpan]
    ) -> EvaluatedAnnotation {
        switch HoleReader.read(callout.anchor, in: topology, frame: frame, parts: parts) {
        case .lost(let reason): return lost(reason, anchors: [status(of: reason)])
        case .notAHole: return lost(.notAHole, anchors: [.held])
        case .hole(let shape, let center, _, let radius):
            let label = DimensionLabel.hole(shape, precision: nil, prefix: callout.prefix, suffix: callout.suffix, format: format)
            return held(
                [.held], labels: [label], values: [shape.diameter], figure: .hole(center: frame.place(center), radius: radius),
                label: label)
        }
    }

    // MARK: Centre marks and lines

    private static func centreMark(
        _ mark: CentreMark, topology: Topology, frame: ProjectionFrame, parts: [PartSpan]
    ) -> EvaluatedAnnotation {
        switch DrawingAnchorResolver.resolve(mark.anchor, in: topology, frame: frame, parts: parts) {
        case .lost(let reason): return lost(reason, anchors: [status(of: reason)])
        case .held(.circle(let center, let axis, let radius, _), _, _):
            guard abs(axis.dot(frame.direction)) >= 1 - 1e-9 else { return lost(.foreshortened, anchors: [.held]) }
            return held(
                [.held], labels: [], values: [radius], figure: .centreMark(center: frame.place(center), radius: radius), label: nil)
        case .held(.point(let center), _, _):
            return held([.held], labels: [], values: [0], figure: .centreMark(center: frame.place(center), radius: 0), label: nil)
        case .held: return lost(.notLineOrCircle, anchors: [.held])
        }
    }

    private static func centreLine(
        _ line: CentreLine, topology whole: Topology, frame: ProjectionFrame, parts: [PartSpan]
    ) -> EvaluatedAnnotation {
        let topology: Topology
        let target: AnchorTarget
        switch DrawingAnchorResolver.scope(of: line.anchor, in: whole, parts: parts) {
        case .failure(let reason): return lost(reason, anchors: [status(of: reason)])
        case .success(let found): (target, topology) = (found.target, found.topology)
        }
        guard case .axis(let pick) = target else { return lost(.notCylinder, anchors: [.held]) }
        switch DrawingAnchorResolver.resolve(target, in: topology, frame: frame, parts: []) {
        case .lost(let reason): return lost(reason, anchors: [status(of: reason)])
        case .held(.cylinder(let axisPoint, let axis, _, _), _, _):
            guard abs(axis.dot(frame.direction)) <= 1e-9 else { return lost(.foreshortened, anchors: [.held]) }
            guard let face = topology.faces(matching: pick).first,
                let span = axialSpan(of: face, axisPoint: axisPoint, axis: axis, in: topology)
            else { return lost(.refused("The cylinder has no circular edges to give its length."), anchors: [.held]) }
            let start = frame.place(axisPoint + axis * span.lowerBound)
            let end = frame.place(axisPoint + axis * span.upperBound)
            return held(
                [.held], labels: [], values: [span.upperBound - span.lowerBound], figure: .centreLine(start: start, end: end),
                label: nil)
        case .held: return lost(.notCylinder, anchors: [.held])
        }
    }

    /// The axial extremes of the face's circular edges, as distances from `axisPoint` along `axis`.
    private static func axialSpan(
        of face: FaceInfo, axisPoint: Vector3, axis: Vector3, in topology: Topology
    ) -> ClosedRange<Double>? {
        var low = Double.infinity, high = -Double.infinity
        for edge in topology.edges where edge.faces.contains(face.id) {
            guard case .circle(let center, let circleAxis, _, _, _)? = edge.curve, abs(circleAxis.dot(axis)) >= 1 - 1e-9 else { continue }
            let t = (center - axisPoint).dot(axis)
            low = Swift.min(low, t)
            high = Swift.max(high, t)
        }
        return low <= high ? low...high : nil
    }
}

extension DimensionLabel {
    /// A label rebuilt from remembered lines, the symbols' plain characters turned back into symbols (plan R15).
    static func restored(from lines: [String]) -> DimensionLabel {
        func pieces(_ line: String) -> [LabelPiece] {
            var result: [LabelPiece] = []
            var text = ""
            for character in line {
                let symbol: LabelSymbol? =
                    switch character {
                    case "↧": .depth
                    case "⌴": .counterbore
                    case "⌵": .countersink
                    default: nil
                    }
                if let symbol {
                    if !text.isEmpty { result.append(.text(text)) }
                    text = ""
                    result.append(.symbol(symbol))
                } else {
                    text.append(character)
                }
            }
            if !text.isEmpty { result.append(.text(text)) }
            return result
        }
        return DimensionLabel(lines: lines.isEmpty ? [[]] : lines.map(pieces))
    }
}
