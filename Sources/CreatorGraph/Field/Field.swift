import CreatorGeometry
import CreatorKernel

/// A value that varies over space (fields spec §2.1): a number at every point. It is an immutable expression tree,
/// `Sendable`, whose leaves hold plain numbers and kernel references (a `Solid`, an `EdgeSet`, a `FaceSet`, a
/// `Profile2D`, a `Plane`) and which holds no samples: `FieldSampler` (CreatorNodes) evaluates it over a batch of points.
/// It is computed, never saved, so it is not `Codable`; `description` is its readable recipe.
///
/// Adding a case means adding it to `children`, to `description` and to the sampler, none of which has a `default`, so the
/// compiler lists the places (Image Field, 7b-2, was the first).
public indirect enum Field: Hashable, Sendable {
    /// What a distance field measures from. A point or a profile is plain Swift maths; anything on a solid asks the kernel.
    public enum DistanceSource: Sendable {
        case point(Vector3)
        /// The profile's loops (its edges, not its area), measured in 3D on its plane.
        case profile(Profile2D)
        case kernel(DistanceTarget)
    }

    // MARK: Sources

    /// The same number everywhere (what a number or integer converts to).
    case constant(Double)
    /// Millimetres from the point to the source; `signed` (a solid only) makes inside negative.
    case distance(DistanceSource, signed: Bool)
    /// The signed distance along `plane`'s normal ÷ `length`: 0 on the plane, 1 one length along the normal, unclamped.
    case linearGradient(plane: Plane, length: Double)
    /// ‖p − center‖ ÷ `radius`.
    case radialGradient(center: Vector3, radius: Double)
    /// Smooth fractal gradient noise in 0…1, hashed from `seed` (fields spec §3.1); `scale` is the feature size in mm.
    case noise(seed: Int, scale: Double, octaves: Int)
    /// A picture projected along `plane`'s normal (fields spec §5): the point's plane coordinates, centred on the plane's origin
    /// and scaled by `width` and `height` millimetres, pick a position in the picture (row 0 at the top, plane +y up), and
    /// the value is the bilinear grey in 0…1. `plane` has unit axes. `width` and `height` must be positive and finite. `edges`
    /// says what lies outside the rectangle. A point so far out that its picture position overflows to infinity
    /// (`GreyImage.value`) has value 0, with either edge mode.
    case image(GreyImage, plane: Plane, width: Double, height: Double, edges: ImageEdges)

    // MARK: Maths

    case add(Field, Field)
    case multiply(Field, Field)
    case minimum(Field, Field)
    case maximum(Field, Field)
    /// The linear map of the from range onto the to range, held to the to range when `clamped`. A from range whose ends
    /// are equal maps everything to `toLow` (the Remap node refuses it before a field is made).
    case remap(Field, fromLow: Double, fromHigh: Double, toLow: Double, toHigh: Double, clamped: Bool)
    case clamp(Field, low: Double, high: Double)
    /// The polynomial smooth minimum of the two over `width` (0 is the plain minimum).
    case smoothMinimum(Field, Field, width: Double)
}
