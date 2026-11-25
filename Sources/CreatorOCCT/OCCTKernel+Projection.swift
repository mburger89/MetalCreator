import COCCT
import CreatorGeometry
import CreatorKernel

/// Hidden-line projection (drawings DR-1, R9 and R10): `occt_projection` reads HLRBRep's data per edge and names each line's source by
/// shape identity.
extension OCCTKernel {
    public func projection(of solid: Solid?, curves: [Curve], frame: ProjectionFrame, options: ProjectionOptions) async throws
        -> Projection2D {
        try Task.checkCancellation()
        try frame.validate()
        guard options.tolerance.isFinite, options.tolerance > 0 else {
            throw KernelError.invalidInput("The projection tolerance must be greater than 0 mm.")
        }
        let solidShape = try solid.map { try shape(of: $0) }
        let curveShapes = try curves.map { try curveShape(of: $0) }
        guard solidShape != nil || !curveShapes.isEmpty else { return Projection2D() }
        let flag = OCCTCancelFlag()
        let raw: RawProjection
        do {
            raw = try await withTaskCancellationHandler {
                // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure.
                try Self.serialized { () throws -> RawProjection in
                    try OCCTShape.projecting(solidShape, curves: curveShapes, frame: frame, tolerance: options.tolerance, cancel: flag)
                }
            } onCancel: {
                flag.cancel()
            }
        } catch let error as OCCTError {
            if error.message == OCCTCancelFlag.message { throw CancellationError() }
            if error.message.hasPrefix("occt: ") { throw KernelError.occt("projection", error) }
            throw KernelError.invalidInput(error.message)
        }
        try Task.checkCancellation()
        return Self.projection(from: raw, solid: solid)
    }

    private static func projection(from raw: RawProjection, solid: Solid?) -> Projection2D {
        var lines: [ProjectedLine] = []
        lines.reserveCapacity(raw.lines.count)
        for line in raw.lines where !line.curve.isZeroLength {
            var lineClass = line.projectedClass
            if case .edge(let id)? = line.projectedSource, let solid, solid.topology.edges.indices.contains(id.rawValue),
               solid.topology.edges[id.rawValue].isBoundary {
                lineClass = .sheetBoundary
            }
            lines.append(ProjectedLine(visibility: line.hidden ? .hidden : .visible, lineClass: lineClass, curve: line.curve,
                                       source: line.projectedSource))
        }
        return Projection2D(lines: lines)
    }
}

/// One line as the shim wrote it.
struct RawProjectedLine {
    var hidden: Bool
    var lineClass: Int
    var sourceKind: Int
    var sourceIndex: Int
    var sourcePiece: Int
    var curve: ProjectedCurve
}

extension RawProjectedLine {
    var projectedSource: ProjectionSource? {
        switch sourceKind {
        case 0: .edge(EdgeID(sourceIndex))
        case 1: .face(FaceID(sourceIndex))
        case 2: .curve(index: sourceIndex, piece: sourcePiece)
        default: nil
        }
    }

    var projectedClass: LineClass {
        switch lineClass {
        case 1: .smooth
        case 2: .outline
        case 4: .curve
        default: .sharp
        }
    }
}

struct RawProjection {
    var lines: [RawProjectedLine]
}

extension ProjectedCurve {
    fileprivate var isZeroLength: Bool {
        switch self {
        case .line(let a, let b): (a - b).length < 1e-9
        case .arc(_, let radius, _, let sweep): radius < 1e-9 || abs(sweep) < 1e-12
        case .ellipse(_, _, let major, _, _, let sweep): major < 1e-9 || abs(sweep) < 1e-12
        case .polyline(let points): points.count < 2
        }
    }
}

extension OCCTShape {
    /// The hidden-line projection of `solid` and `curves` (`occt_projection`). Call under `OCCTKernel.serialized`.
    static func projecting(_ solid: OCCTShape?, curves: [OCCTShape], frame: ProjectionFrame, tolerance: Double, cancel: OCCTCancelFlag)
        throws(OCCTError) -> RawProjection {
        var result = occt_projection_result()
        defer { occt_projection_free(&result) }
        let direction = [frame.direction.x, frame.direction.y, frame.direction.z]
        let up = [frame.up.x, frame.up.y, frame.up.z]
        let pointers: [OpaquePointer?] = curves.map(\.raw)
        try check { status in
            pointers.withUnsafeBufferPointer { buffer in
                occt_projection(solid?.raw, buffer.baseAddress, Int32(buffer.count), direction, up, tolerance, cancel.raw, &result, status)
            }
        }
        let points = UnsafeBufferPointer(start: result.points, count: Int(result.point_count) * 2)
        let raws = UnsafeBufferPointer(start: result.lines, count: Int(result.line_count))
        let lines = raws.map { line -> RawProjectedLine in
            let n = withUnsafeBytes(of: line.numbers) { Array($0.bindMemory(to: Double.self)) }
            let curve: ProjectedCurve
            switch line.geometry {
            case 0: curve = .line(Vector2(n[0], n[1]), Vector2(n[2], n[3]))
            case 1: curve = .arc(center: Vector2(n[0], n[1]), radius: n[2], start: n[3], sweep: n[4])
            case 2:
                curve = .ellipse(center: Vector2(n[0], n[1]), majorAxis: Vector2(n[2], n[3]), majorRadius: n[4], minorRadius: n[5],
                                 start: n[6], sweep: n[7])
            default:
                let first = Int(line.point_offset)
                curve = .polyline((first..<(first + Int(line.point_count))).map { Vector2(points[$0 * 2], points[$0 * 2 + 1]) })
            }
            return RawProjectedLine(hidden: line.visibility != 0, lineClass: Int(line.line_class), sourceKind: Int(line.source_kind),
                                    sourceIndex: Int(line.source_index), sourcePiece: Int(line.source_piece), curve: curve)
        }
        return RawProjection(lines: lines)
    }
}
