import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport

/// A plane the section is measured from: a point on it, the side that is cut away when the section is not flipped, and the
/// direction a positive offset moves it.
struct SectionFrame: Equatable, Sendable {
    /// A point of the reference plane.
    var origin: Vector3
    /// Unit; the side cut away when unflipped.
    var normal: Vector3
    /// Unit; `+normal` for an origin plane, `-normal` (into the material) for a face.
    var offsetDirection: Vector3
}

extension SliceAxis {
    init(_ origin: SectionOrigin) {
        switch origin {
        case .xy: self = .xy
        case .yz: self = .yz
        case .xz: self = .xz
        }
    }

    var origin: SectionOrigin {
        switch self {
        case .xy: .xy
        case .yz: .yz
        case .xz: .xz
        }
    }
}

/// The section view's geometry (section spec §3.1, §3.2, §3.5): settings and the scene in, a plane, a clip and a handle out.
/// Pure, so the model and the app can both ask it.
enum SectionGeometry {
    /// An origin plane: through the origin, its offset along its normal.
    static func frame(of origin: SectionOrigin) -> SectionFrame {
        let normal = SliceAxis(origin).plane.normal
        return SectionFrame(origin: .zero, normal: normal, offsetDirection: normal)
    }

    /// A flat face with a normal: through its centroid, an offset going into the material (against the outward normal).
    /// `nil` for a curved face, which has no plane to cut along.
    static func frame(ofFace face: FaceInfo) -> SectionFrame? {
        guard face.kind == .plane, let normal = face.normal?.normalized, normal.isFinite else { return nil }
        return SectionFrame(origin: face.centroid, normal: normal, offsetDirection: -normal)
    }

    /// The face a pick names in the scene, and whether the pick could only be guessed at. The first part (scene order) that is no
    /// ghost and no guide and whose faces answer the pick with a flat face wins.
    static func resolveFace(_ pick: FacePick, in items: [ViewportItem]) -> (face: FaceInfo, isGuess: Bool)? {
        for item in items where !item.isGuide && !item.isGhost {
            let resolution = item.solid.topology.resolution(of: pick)
            if let face = resolution.faces.first, frame(ofFace: face) != nil {
                return (face, resolution.isAmbiguous)
            }
        }
        return nil
    }

    /// The viewport's clip for a plane `offset` mm from the frame; flipping cuts the other side.
    static func clip(_ frame: SectionFrame, offset: Double, isFlipped: Bool) -> ViewportClip {
        ViewportClip(origin: frame.origin + frame.offsetDirection * offset,
                     normal: isFlipped ? -frame.normal : frame.normal)
    }

    /// The handle that moves the plane: anchored at the part's centre projected into the reference plane, its range the part's
    /// reach along the offset direction, widened to a typed offset beyond it.
    static func handle(_ frame: SectionFrame, offset: Double, bounds: BoundingBox) -> ViewportHandle {
        let centre = bounds.center
        let anchor = centre - frame.normal * (centre - frame.origin).dot(frame.normal)
        let spans = corners(of: bounds).map { ($0 - frame.origin).dot(frame.offsetDirection) }
        let low = min(spans.min() ?? 0, offset), high = max(spans.max() ?? 0, offset)
        return ViewportHandle(id: SectionModel.handleID, anchor: anchor, direction: frame.offsetDirection, value: offset,
                              range: low...high, style: .linear, tint: .solid)
    }

    /// How a section starts: the chosen origin plane, or the axis plane nearest the view direction, through the part's centre,
    /// cutting the side that faces the viewer.
    static func starting(origin: SectionOrigin?, bounds: BoundingBox, toEye: Vector3) -> SectionSettings {
        let chosen = origin ?? SlicePose.startingAxis(toEye: toEye).origin
        let normal = frame(of: chosen).normal
        return SectionSettings(isOn: true, reference: .origin(chosen), offset: bounds.center.dot(normal),
                               isFlipped: toEye.dot(normal) < 0)
    }

    private static func corners(of box: BoundingBox) -> [Vector3] {
        [box.min.x, box.max.x].flatMap { x in
            [box.min.y, box.max.y].flatMap { y in [box.min.z, box.max.z].map { Vector3(x, y, $0) } }
        }
    }
}
