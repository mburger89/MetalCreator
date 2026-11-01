import Foundation

/// How smoothly two faces meet along an edge: G0 (touch), G1 (same tangent plane) or G2 (same curvature too).
public enum ContinuityClass: Int, Comparable, Sendable {
    case g0, g1, g2

    public static func < (lhs: ContinuityClass, rhs: ContinuityClass) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// The worst gaps between the two faces that meet at an edge, sampled along it (`Kernel.continuity(along:of:)`).
public struct EdgeContinuity: Equatable, Sendable {
    /// Millimetres, the worst sample.
    public var positionGap: Double
    /// Radians, the worst angle between the faces' outward normals.
    public var angleGap: Double
    /// `|κ1 − κ2| / max(|κ1|, |κ2|)` of the normal curvatures across the edge, the worst over the samples whose absolute gap exceeds
    /// `curvatureFloor` (0 when none does).
    public var curvatureGap: Double
    /// `|κ1 − κ2|`, per millimetre.
    public var absoluteCurvatureGap: Double
    /// The class these gaps reach against the tolerances.
    public var grade: ContinuityClass

    /// Millimetres.
    public static let positionTolerance = 1e-4
    /// Radians (0.01°).
    public static let angleTolerance = 0.01 * Double.pi / 180
    /// Relative: 1 % of the larger curvature.
    public static let curvatureTolerance = 0.01
    /// Per millimetre: curvatures under this count as flat.
    public static let curvatureFloor = 1e-4

    public init(positionGap: Double, angleGap: Double, curvatureGap: Double, absoluteCurvatureGap: Double) {
        self.positionGap = positionGap
        self.angleGap = angleGap
        self.curvatureGap = curvatureGap
        self.absoluteCurvatureGap = absoluteCurvatureGap
        self.grade = Self.grade(positionGap: positionGap, angleGap: angleGap, curvatureGap: curvatureGap,
                                absoluteCurvatureGap: absoluteCurvatureGap)
    }

    /// G1 needs the position and the angle within tolerance; G2 also the curvature, within 1 % of the larger or `curvatureFloor`
    /// absolute, whichever is larger.
    public static func grade(positionGap: Double, angleGap: Double, curvatureGap: Double,
                             absoluteCurvatureGap: Double) -> ContinuityClass {
        guard positionGap <= positionTolerance, angleGap <= angleTolerance else { return .g0 }
        return curvatureGap <= curvatureTolerance || absoluteCurvatureGap <= curvatureFloor ? .g2 : .g1
    }
}
