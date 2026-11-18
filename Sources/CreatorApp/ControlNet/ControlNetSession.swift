import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport
import Observation

/// The poles of the net being edited as they stand before any move: row-major, `i * vCount + j`, `i` along u. A curve has
/// `vCount` 1 and no normals; a surface's normal is the one at each pole's Greville parameters.
struct ControlNetGrid: Equatable {
    var poles: [Vector3]
    var uCount: Int
    var vCount: Int
    var normals: [Vector3]

    func pole(_ index: PoleIndex) -> Vector3? {
        guard contains(index) else { return nil }
        return poles[index.i * vCount + index.j]
    }

    func normal(_ index: PoleIndex) -> Vector3? {
        guard contains(index), index.i * vCount + index.j < normals.count else { return nil }
        return normals[index.i * vCount + index.j]
    }

    func contains(_ index: PoleIndex) -> Bool {
        index.i >= 0 && index.i < uCount && index.j >= 0 && index.j < vCount && index.i * vCount + index.j < poles.count
    }
}

/// A rectangle on screen, in viewport points, y down.
struct ScreenRect: Equatable {
    var minX: Double
    var minY: Double
    var maxX: Double
    var maxY: Double

    init(_ a: ScreenPoint, _ b: ScreenPoint) {
        minX = min(a.x, b.x)
        maxX = max(a.x, b.x)
        minY = min(a.y, b.y)
        maxY = max(a.y, b.y)
    }

    func contains(_ point: ScreenPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }
}

/// The control-net tool (NS-3, rulings R5, R7 and R8): the poles of one surface or curve are shown over the model, picked by a
/// click or a box, and dragged in the plane facing the camera, along an axis lock, or along the grabbed point's normal. It makes
/// no command: it reports each pole's new total offset from its base position through `events`, and the app stores them.
@MainActor
@Observable
final class ControlNetSession: ViewportTool {
    enum Kind: Hashable { case surface, curve }

    /// How a report of moves came about: a drag step, the release of a drag, or a value typed into the inspector.
    enum DragPhase: Hashable { case changed, ended, typed }

    enum AxisLock: Hashable { case x, y, z, normal }

    struct Events {
        /// Every moved point's new total offset from its base pole, with how it came about.
        var moved: ([PoleMove], DragPhase) -> Void
        /// The mode ended (Esc or Done).
        var ended: () -> Void

        init(moved: @escaping ([PoleMove], DragPhase) -> Void = { _, _ in }, ended: @escaping () -> Void = {}) {
            self.moved = moved
            self.ended = ended
        }
    }

    /// How far from a pole a click still picks it, in points (R8).
    static let pickRadius = 8.0

    let node: NodeID
    let kind: Kind
    private(set) var net = ControlNetGrid(poles: [], uCount: 0, vCount: 0, normals: [])
    internal(set) var offsets: [PoleIndex: Vector3] = [:]
    var selection: Set<PoleIndex> = []
    private(set) var lock: AxisLock?
    private(set) var hover: PoleIndex?
    internal(set) var boxRect: ScreenRect?
    @ObservationIgnored var events: Events
    @ObservationIgnored var drag: Drag?

    init(node: NodeID, kind: Kind, events: Events) {
        self.node = node
        self.kind = kind
        self.events = events
    }

    /// Shows `net` with `moves` applied. A net of another size clears the selection; while a drag is under way the net on screen stays.
    func showNet(_ net: ControlNetGrid, moves: [PoleMove]) {
        guard drag == nil else { return }
        if net.uCount != self.net.uCount || net.vCount != self.net.vCount { selection = [] }
        self.net = net
        offsets = [:]
        for move in moves where net.contains(move.index) { offsets[move.index] = move.offset }
        selection = selection.filter { net.contains($0) }
        if let hover, !net.contains(hover) { self.hover = nil }
    }

    /// The pole's place now: its base position and its offset.
    func position(of index: PoleIndex) -> Vector3? {
        net.pole(index).map { $0 + (offsets[index] ?? .zero) }
    }

    /// Sets the lock, or lifts it when it already is the lock. A normal lock does nothing on a curve (R5).
    func toggleLock(_ lock: AxisLock) {
        if lock == .normal, kind == .curve { return }
        self.lock = self.lock == lock ? nil : lock
    }

    /// Types one component (0 x, 1 y, 2 z) of the one selected point's offset.
    func setOffset(_ component: Int, to value: Double) {
        guard selection.count == 1, let index = selection.first, net.contains(index), (0..<3).contains(component) else { return }
        var offset = offsets[index] ?? .zero
        switch component {
        case 0: offset.x = value
        case 1: offset.y = value
        default: offset.z = value
        }
        offsets[index] = offset
        events.moved([PoleMove(index: index, offset: offset)], .typed)
    }

    /// Esc and Done: the mode ends.
    func cancel() {
        drag = nil
        boxRect = nil
        events.ended()
    }

    func done() { cancel() }

    // MARK: - ViewportTool

    var offersSectionFromFace: Bool { false }

    func pointerMoved(to point: ScreenPoint?, modifiers: ViewportModifiers, projector: ViewportProjector) {
        guard drag == nil else { return }
        hover = point.flatMap { pole(at: $0, projector: projector) }
    }

    func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool {
        guard let hit = pole(at: point, projector: projector) else {
            if modifiers.isDisjoint(with: [.shift, .command]) { selection = [] }
            return true
        }
        if modifiers.contains(.command) {
            if selection.contains(hit) { selection.remove(hit) } else { selection.insert(hit) }
        } else if modifiers.contains(.shift) {
            selection.insert(hit)
        } else {
            selection = [hit]
        }
        return true
    }

    /// The pole within `pickRadius` points of `point`: the nearest on screen, the nearest to the camera when two are as near.
    func pole(at point: ScreenPoint, projector: ViewportProjector) -> PoleIndex? {
        let toEye = projector.pose.toEye
        var best: (index: PoleIndex, distance: Double, depth: Double)?
        for i in 0..<net.uCount {
            for j in 0..<net.vCount {
                let index = PoleIndex(i: i, j: j)
                guard let world = position(of: index), let screen = projector.screenPoint(of: world) else { continue }
                let distance = ((screen.x - point.x) * (screen.x - point.x) + (screen.y - point.y) * (screen.y - point.y)).squareRoot()
                guard distance <= Self.pickRadius else { continue }
                let depth = world.dot(toEye)
                if let current = best {
                    if distance < current.distance - 1e-9 || (abs(distance - current.distance) <= 1e-9 && depth > current.depth) {
                        best = (index, distance, depth)
                    }
                } else {
                    best = (index, distance, depth)
                }
            }
        }
        return best?.index
    }
}
