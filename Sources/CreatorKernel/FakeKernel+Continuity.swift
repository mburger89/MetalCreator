import Foundation
import CreatorGeometry

extension FakeKernel {
    /// A test knob: runs at the start of every `continuity`; it may throw to refuse. `nil` (the default) does nothing.
    public func setContinuityHook(_ hook: (@Sendable () throws -> Void)?) {
        continuityHook = hook
    }

    public func continuity(along edge: EdgeID, of solid: Solid) throws -> EdgeContinuity {
        try continuityHook?()
        try Task.checkCancellation()
        operationLog.append("continuity")
        return try Self.continuity(along: edge, of: solid)
    }

    /// Continuity between two planar faces from their normals; a curved face is refused.
    static func continuity(along edge: EdgeID, of solid: Solid) throws -> EdgeContinuity {
        guard let info = solid.topology.edges.first(where: { $0.id == edge }) else {
            throw KernelError.invalidInput("That edge no longer exists.")
        }
        let faces = info.faces.compactMap { solid.topology.face($0) }
        guard !info.isSeam, faces.count == 2, faces[0].id != faces[1].id else { throw KernelError.unsupported("continuity of a seam") }
        guard faces.allSatisfy({ $0.kind == .plane }) else { throw KernelError.unsupported("continuity of a curved face") }
        let angle: Double
        switch (faces[0].normal?.normalized, faces[1].normal?.normalized) {
        case (let first?, let second?):
            angle = atan2(first.cross(second).length, first.dot(second))
        case (let cap?, nil), (nil, let cap?):
            // A Fake prism's walls carry no normal but stand square on the caps: the edge between a cap and a wall is a right angle.
            guard let along = info.direction?.normalized, abs(along.dot(cap)) < 1e-9 else {
                throw KernelError.unsupported("continuity of a face with no normal")
            }
            angle = .pi / 2
        default:
            throw KernelError.unsupported("continuity of a face with no normal")
        }
        return EdgeContinuity(positionGap: 0, angleGap: angle, curvatureGap: 0, absoluteCurvatureGap: 0)
    }
}
