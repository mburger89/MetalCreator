import COCCT
import CreatorGeometry
import CreatorKernel
import Foundation

/// Curves (NURBS spec): wires of lines, arcs and B-splines, interpolated curves and the curves of a solid's edges.
extension OCCTKernel {
    /// How far a degree-5 curve may stand from a point it should pass through, in millimetres.
    static let interpolationTolerance = 1e-6

    public func makeCurve(_ pieces: [CurvePiece], tag: NodeTag) throws -> Curve {
        try Task.checkCancellation()
        guard !pieces.isEmpty else { throw KernelError.invalidInput("A curve needs at least one piece.") }
        for case .spline(let spline) in pieces where !spline.isWellFormed { throw KernelError.malformedSpline }
        for (a, b) in zip(pieces, pieces.dropFirst()) where (a.end - b.start).length > 1e-6 {
            throw KernelError.invalidInput("The curve's pieces don't join end to end.")
        }
        let wire = try curveShape("make curve") { try OCCTShape.makeCurve(pieces) }
        return try curve(from: wire, operation: "make curve")
    }

    public func interpolate(_ points: [Vector3], degree: Int, closed: Bool, startTangent: Vector3?, endTangent: Vector3?,
                            tag: NodeTag) throws -> Curve {
        try interpolate(points, degree: degree, closed: closed, startTangent: startTangent, endTangent: endTangent,
                        maxDeviation: Self.interpolationTolerance)
    }

    /// `interpolate` with the largest distance a degree-5 curve may stand from a point (the public one asks for 1e-6 mm).
    func interpolate(_ points: [Vector3], degree: Int, closed: Bool, startTangent: Vector3?, endTangent: Vector3?,
                     maxDeviation: Double) throws -> Curve {
        try Task.checkCancellation()
        try Self.validateInterpolation(points, degree: degree, closed: closed, startTangent: startTangent, endTangent: endTangent)
        let wire = try curveShape("interpolate") {
            try OCCTShape.interpolatedCurve(points, degree: degree, closed: closed, startTangent: startTangent,
                                            endTangent: endTangent, maxDeviation: maxDeviation)
        }
        return try curve(from: wire, operation: "interpolate")
    }

    private static func validateInterpolation(_ points: [Vector3], degree: Int, closed: Bool, startTangent: Vector3?,
                                              endTangent: Vector3?) throws {
        guard degree == 3 || degree == 5 else { throw KernelError.invalidInput("The curve's degree must be 3 or 5.") }
        guard points.allSatisfy(\.isFinite) else { throw KernelError.invalidInput("The points must be finite numbers.") }
        if degree == 5 {
            guard points.count >= 6 else { throw KernelError.invalidInput("A degree-5 curve needs at least six points.") }
            guard !closed else { throw KernelError.invalidInput("A closed curve needs degree 3.") }
            guard startTangent == nil, endTangent == nil else { throw KernelError.invalidInput("End tangents need degree 3.") }
        }
        guard points.count >= (closed ? 3 : 2) else {
            throw KernelError.invalidInput(closed ? "A closed curve needs at least three points." : "A curve needs at least two points.")
        }
        guard !closed || (startTangent == nil && endTangent == nil) else {
            throw KernelError.invalidInput("A closed curve can't have end tangents.")
        }
        try validateSpacing(points, closed: closed)
        for tangent in [startTangent, endTangent].compactMap({ $0 }) where tangent.length < 1e-12 || !tangent.isFinite {
            throw KernelError.invalidInput("A tangent can't be zero.")
        }
    }

    private static func validateSpacing(_ points: [Vector3], closed: Bool) throws {
        for pair in zip(points.indices, points.indices.dropFirst()) where (points[pair.0] - points[pair.1]).length < 1e-6 {
            throw KernelError.invalidInput("Points \(pair.0 + 1) and \(pair.1 + 1) are in the same place.")
        }
        if closed, let last = points.last, let first = points.first, (last - first).length < 1e-6 {
            throw KernelError.invalidInput("Points \(points.count) and 1 are in the same place.")
        }
    }

    public func curves(from edges: [EdgeID], of solid: Solid, tag: NodeTag) throws -> [Curve] {
        try Task.checkCancellation()
        guard !edges.isEmpty else { throw KernelError.invalidInput("Pick at least one edge.") }
        let count = solid.topology.edges.count
        guard edges.allSatisfy({ (0..<count).contains($0.rawValue) }) else {
            throw KernelError.invalidInput("That edge no longer exists.")
        }
        let source = try shape(of: solid)
        let indices = Array(Set(edges.map(\.rawValue))).sorted().map { Int32($0 + 1) }
        let compound = try curveShape("curves from edges") { try source.curves(fromEdges: indices) }
        let wires = try Self.serialized { () throws -> [OCCTShape] in try compound.children() }
        return try wires.map { try curve(from: $0, operation: "curves from edges") }
    }

    /// Runs a shim builder under the kernel lock, mapping its failure to a `KernelError` in the shim's own words.
    func curveShape(_ operation: String, _ body: () throws -> OCCTShape) throws -> OCCTShape {
        do {
            // Untyped throws on purpose: Swift 6.4 IRGen crashes with typed throws in this closure.
            return try Self.serialized { () throws -> OCCTShape in try body() }
        } catch let error as OCCTError {
            if error.message.hasPrefix("occt: ") { throw KernelError.occt(operation, error) }
            throw KernelError.invalidInput(error.message)
        }
    }

    /// The `Curve` for a wire: its facts read once, the wire kept as the storage.
    func curve(from wire: OCCTShape, operation: String) throws -> Curve {
        let info: OCCTCurveInfo
        do {
            info = try Self.serialized { () throws -> OCCTCurveInfo in try wire.curveInfo() }
        } catch let error as OCCTError {
            throw KernelError.occt(operation, error)
        }
        return Curve(pieceCount: info.pieceCount, isClosed: info.isClosed, plane: info.plane, length: info.length,
                     bounds: info.bounds, polyline: info.polyline, storage: OCCTSolidStorage(shape: wire, faceCount: 0))
    }

    /// The distance from `point` to a curve made by this kernel. For tests.
    func distance(from point: Vector3, to curve: Curve) throws -> Double {
        guard let storage = curve.storage as? OCCTSolidStorage else {
            throw KernelError.invalidInput("This curve was made by a different kernel.")
        }
        do {
            return try Self.serialized { () throws -> Double in try storage.shape.curveDistance(to: point) }
        } catch let error as OCCTError {
            throw KernelError.occt("distance", error)
        }
    }

    /// The degree and pole count of a curve's first piece, a spline. For tests.
    func splineInfo(of curve: Curve) throws -> (degree: Int, poleCount: Int) {
        guard let storage = curve.storage as? OCCTSolidStorage else {
            throw KernelError.invalidInput("This curve was made by a different kernel.")
        }
        do {
            return try Self.serialized { () throws -> (degree: Int, poleCount: Int) in try storage.shape.firstSplineInfo() }
        } catch let error as OCCTError {
            throw KernelError.occt("spline info", error)
        }
    }
}
