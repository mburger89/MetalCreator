import CreatorGeometry
import CreatorViewport
import Observation

/// The cut view (implicit spec §5.1): a plane through the scene that cuts the near half away, so a lattice can be seen inside its
/// skin. It reuses 7b's slice plane: the same `SlicePose` (an axis plane through the part's box, moved along its normal) and the same
/// handle. Switching it on picks the axis plane nearest the view direction and cuts away the side that faces the viewer; Flip cuts the
/// other side. View state in memory, never saved, never an undo step. Only the Metal viewport draws the cut; the Linux and Windows
/// viewport is a placeholder, so there the controls are not offered (`isAvailable`).
@MainActor
@Observable
final class CutViewModel {
    static let handleID = "cut-plane"

    /// Whether this build's viewport can draw a cut.
    static var isAvailable: Bool {
        #if canImport(Metal)
        true
        #else
        false
        #endif
    }

    /// Bumped by every change the scene might draw; `AppModel` observes only this.
    private(set) var revision = 0
    private(set) var isOn = false
    private(set) var axis = SliceAxis.xy
    private(set) var offset = 0.0
    private(set) var isFlipped = false
    private(set) var bounds: BoundingBox?
    /// Which way the plane's normal pointed relative to the viewer when it was made: the side that faced the viewer is the one cut.
    private var eyeSide = 1.0

    /// Switches the cut view on over a scene inside `bounds`, seen from the direction `toEye`. With nothing in the scene it stays off.
    func turnOn(bounds: BoundingBox?, toEye: Vector3) {
        guard !isOn, let bounds else { return }
        self.bounds = bounds
        axis = SlicePose.startingAxis(toEye: toEye)
        eyeSide = toEye.dot(axis.plane.normal) >= 0 ? 1 : -1
        (offset, isFlipped, isOn) = (0, false, true)
        revision += 1
    }

    func turnOff() {
        guard isOn else { return }
        (isOn, bounds, offset, isFlipped) = (false, nil, 0, false)
        revision += 1
    }

    /// The scene changed: the plane follows the part's new box. Nothing in the scene keeps the last one.
    func follow(bounds newBounds: BoundingBox?) {
        guard isOn, let newBounds, newBounds != bounds else { return }
        bounds = newBounds
        revision += 1
    }

    /// Moves the plane along its normal, held to the part's reach.
    func move(to newOffset: Double) {
        guard isOn, let pose else { return }
        let moved = pose.moved(to: newOffset).offset
        guard moved != offset else { return }
        offset = moved
        revision += 1
    }

    /// Cuts away the other side.
    func flip() {
        guard isOn else { return }
        isFlipped.toggle()
        revision += 1
    }

    /// The plane's pose now, or `nil` when the cut view is off.
    var pose: SlicePose? {
        guard isOn, let bounds else { return nil }
        return SlicePose.through(axis, bounds: bounds).moved(to: offset)
    }

    /// The plane for the viewport, or `nil` when off.
    var clip: ViewportClip? {
        guard let pose else { return nil }
        let side = eyeSide * (isFlipped ? -1 : 1)
        return ViewportClip(origin: pose.worldPlane.origin, normal: pose.plane.normal * side)
    }

    /// The handle that moves the plane (the slice's, in the same place and style).
    var handle: ViewportHandle? {
        guard let pose else { return nil }
        return ViewportHandle(id: Self.handleID, anchor: pose.plane.origin, direction: pose.plane.normal, value: offset,
                              range: -pose.offsetLimit...pose.offsetLimit, style: .linear, tint: .solid)
    }
}
