import CreatorGeometry
import Foundation

/// A rigid frame: `apply` is origin + x·xAxis + y·yAxis + z·zAxis. Never a mirror (determinant +1).
public struct ModelFrame: Sendable, Equatable {
    public var origin: Vector3
    public var xAxis: Vector3
    public var yAxis: Vector3
    public var zAxis: Vector3

    public init(origin: Vector3, xAxis: Vector3, yAxis: Vector3, zAxis: Vector3) {
        self.origin = origin
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.zAxis = zAxis
    }

    public func apply(_ point: Vector3) -> Vector3 {
        Vector3(origin.x + point.x * xAxis.x + point.y * yAxis.x + point.z * zAxis.x,
                origin.y + point.x * xAxis.y + point.y * yAxis.y + point.z * zAxis.y,
                origin.z + point.x * xAxis.z + point.y * yAxis.z + point.z * zAxis.z)
    }
}

public enum ModelPlacement {
    private typealias Matrix = [[Double]]

    /// Board-local frame of a model (facts §3). With p = (place.origin − boardOrigin) and z0 = back ? 0 : thickness:
    /// M = T(p.x, p.y, z0) · Rz(angle) · [back: Rx(π)] · T(offset) · Rz(−rz) · Ry(−ry) · Rx(−rx)
    /// (degrees; the model's scale is applied to the model beforehand, not here). `angle` is the footprint's, unchanged when back.
    public static func frame(of model: ModelReference, on footprint: Footprint, boardOrigin: Vector2,
                             thickness: Double) -> ModelFrame {
        let rotation = model.rotation
        var chain = multiply(multiply(rotationZ(-rotation.z), rotationY(-rotation.y)), rotationX(-rotation.x))
        var offset = [model.offset.x, model.offset.y, model.offset.z]
        var footprintTurn = rotationZ(footprint.place.angle)
        if footprint.isBack { footprintTurn = multiply(footprintTurn, rotationX(180)) }
        chain = multiply(footprintTurn, chain)
        offset = apply(footprintTurn, offset)
        let place = footprint.place.origin - boardOrigin
        let z0 = footprint.isBack ? 0 : thickness
        return ModelFrame(origin: Vector3(place.x + offset[0], place.y + offset[1], z0 + offset[2]),
                          xAxis: Vector3(chain[0][0], chain[1][0], chain[2][0]),
                          yAxis: Vector3(chain[0][1], chain[1][1], chain[2][1]),
                          zAxis: Vector3(chain[0][2], chain[1][2], chain[2][2]))
    }

    private static func multiply(_ lhs: Matrix, _ rhs: Matrix) -> Matrix {
        (0..<3).map { row in (0..<3).map { col in (0..<3).reduce(0) { $0 + lhs[row][$1] * rhs[$1][col] } } }
    }

    private static func apply(_ matrix: Matrix, _ vector: [Double]) -> [Double] {
        (0..<3).map { row in (0..<3).reduce(0) { $0 + matrix[row][$1] * vector[$1] } }
    }

    /// Exact quarter and half turns, so a 90 or 180 degree angle leaves no 6e-17 residue.
    private static func sineCosine(_ degrees: Double) -> (Double, Double) {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        switch wrapped {
        case 0: return (0, 1)
        case 90, -270: return (1, 0)
        case 180, -180: return (0, -1)
        case 270, -90: return (-1, 0)
        default:
            let radians = degrees * .pi / 180
            return (sin(radians), cos(radians))
        }
    }

    private static func rotationX(_ degrees: Double) -> Matrix {
        let (s, c) = sineCosine(degrees)
        return [[1, 0, 0], [0, c, -s], [0, s, c]]
    }

    private static func rotationY(_ degrees: Double) -> Matrix {
        let (s, c) = sineCosine(degrees)
        return [[c, 0, s], [0, 1, 0], [-s, 0, c]]
    }

    private static func rotationZ(_ degrees: Double) -> Matrix {
        let (s, c) = sineCosine(degrees)
        return [[c, -s, 0], [s, c, 0], [0, 0, 1]]
    }
}
