import Foundation

extension Plane {
    /// The rigid move that carries the world frame onto this plane (patterns spec §3): the origin goes to `origin`,
    /// +X to the plane's x axis, +Y to `yAxis` and +Z to its normal. A tool built at the origin facing +Z, moved by
    /// it, sits on the plane facing along its normal. `xAxis` is first made perpendicular to the normal, so a plane
    /// whose axes are slightly off still gives a rigid move. `nil` for a plane with no usable direction: a zero or
    /// non-finite normal, an x axis along the normal, or a non-finite origin.
    public var placement: Transform? {
        guard origin.isFinite, normal.isFinite, xAxis.isFinite, let z = normal.normalized,
              let x = (xAxis - z * xAxis.dot(z)).normalized else { return nil }
        let y = z.cross(x)
        // The rotation's columns are the images of X, Y and Z.
        let m = [[x.x, y.x, z.x], [x.y, y.y, z.y], [x.z, y.z, z.z]]
        let cosine = min(1, max(-1, (m[0][0] + m[1][1] + m[2][2] - 1) / 2))
        // The unnormalised axis is 2 sin(angle) times the unit axis.
        let raw = Vector3(m[2][1] - m[1][2], m[0][2] - m[2][0], m[1][0] - m[0][1])
        let sine = raw.length / 2
        let around = Axis(origin: .zero, direction: raw)
        if sine > 1e-6, raw.normalized != nil {
            return Transform(translation: origin, rotationAxis: around, rotation: Angle(radians: atan2(sine, cosine)))
        }
        guard cosine < 0 else { return Transform(translation: origin) }
        // A half turn: R + Rᵀ = 4·k·kᵀ − 2·I, so take k from the column of the largest diagonal entry.
        let diagonal = (0..<3).map { m[$0][$0] }
        guard let i = diagonal.indices.max(by: { diagonal[$0] < diagonal[$1] }) else { return nil }
        let k = (0..<3).map { j in
            j == i ? ((m[i][i] + 1) / 2).squareRoot() : (m[i][j] + m[j][i]) / (4 * ((m[i][i] + 1) / 2).squareRoot())
        }
        return Transform(translation: origin, rotationAxis: Axis(origin: .zero, direction: Vector3(k[0], k[1], k[2])),
                         rotation: Angle(radians: .pi))
    }
}
