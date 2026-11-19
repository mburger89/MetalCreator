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
    /// The net closes on itself in this direction: the last pole is joined to the first by a line.
    var periodicU = false
    var periodicV = false

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

    /// How a report of moves came about: a drag step, the release of a drag, a value typed into the inspector, or a cancelled drag
    /// (the moves are then every selected point's offset from before it).
    enum DragPhase: Hashable { case changed, ended, typed, cancelled }

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
    /// For each pole that shares its base position with others (within `SurfaceNet.coincidence`: an apex, a collapsed row), those others. A pole alone
    /// is not here. Poles move and are picked together so a dome's apex never opens.
    @ObservationIgnored private(set) var coincident: [PoleIndex: Set<PoleIndex>] = [:]
    /// A net shown while a drag was under way, applied when it ends.
    @ObservationIgnored var pendingNet: (net: ControlNetGrid, moves: [PoleMove])?

    init(node: NodeID, kind: Kind, events: Events) {
        self.node = node
        self.kind = kind
        self.events = events
    }

    /// Shows `net` with `moves` applied. A net of another size clears the selection; while a drag is under way the net on screen stays and the newer one waits for its end.
    func showNet(_ net: ControlNetGrid, moves: [PoleMove]) {
        guard drag == nil else {
            pendingNet = (net, moves)
            return
        }
        if net.uCount != self.net.uCount || net.vCount != self.net.vCount { selection = [] }
        self.net = net
        coincident = Self.coincidentPoles(in: net)
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

    /// The selection's smallest index when the selection is exactly one coincident group (a lone pole is a group of one), else `nil`.
    var typedTarget: PoleIndex? {
        guard let first = selection.min(), net.contains(first), group(of: first) == selection else { return nil }
        return first
    }

    /// Types one component (0 x, 1 y, 2 z) of the selected point's offset; a group of coincident poles moves together.
    func setOffset(_ component: Int, to value: Double) {
        guard let target = typedTarget, (0..<3).contains(component) else { return }
        var offset = offsets[target] ?? .zero
        switch component {
        case 0: offset.x = value
        case 1: offset.y = value
        default: offset.z = value
        }
        let members = selection.sorted()
        for index in members { offsets[index] = offset }
        events.moved(members.map { PoleMove(index: $0, offset: offset) }, .typed)
    }

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
        let group = group(of: hit)
        if modifiers.contains(.command) {
            if selection.contains(hit) { selection.subtract(group) } else { selection.formUnion(group) }
        } else if modifiers.contains(.shift) {
            selection.formUnion(group)
        } else {
            selection = group
        }
        return true
    }

    /// `index` and every pole that sits on the same point.
    func group(of index: PoleIndex) -> Set<PoleIndex> {
        (coincident[index] ?? []).union([index])
    }

    /// `selection` with each pole's coincident poles added.
    func expanded(_ selection: Set<PoleIndex>) -> Set<PoleIndex> {
        selection.reduce(into: selection) { $0.formUnion(coincident[$1] ?? []) }
    }

    private struct Bucket: Hashable {
        var x: Int
        var y: Int
        var z: Int
    }

    private static func neighbours(of key: Bucket, in buckets: [Bucket: [Int]]) -> [Int] {
        var found: [Int] = []
        for dx in -1...1 {
            for dy in -1...1 {
                for dz in -1...1 {
                    let (x, ox) = key.x.addingReportingOverflow(dx)
                    let (y, oy) = key.y.addingReportingOverflow(dy)
                    let (z, oz) = key.z.addingReportingOverflow(dz)
                    if !(ox || oy || oz), let others = buckets[Bucket(x: x, y: y, z: z)] { found += others }
                }
            }
        }
        return found
    }

    /// Poles within `SurfaceNet.coincidence` of one another, grouped transitively: poles are bucketed by `floor(coordinate / coincidence)`
    /// per axis, each is compared with the poles of the 27 buckets around it, and the connected sets (union-find) are the groups.
    private static func coincidentPoles(in net: ControlNetGrid) -> [PoleIndex: Set<PoleIndex>] {
        guard net.poles.count == net.uCount * net.vCount, net.poles.count > 1 else { return [:] }
        let tolerance = SurfaceNet.coincidence
        func cell(_ value: Double) -> Int {
            let scaled = (value / tolerance).rounded(.down)
            guard scaled.isFinite else { return 0 }
            return Int(max(-4e18, min(4e18, scaled)))
        }
        var buckets: [Bucket: [Int]] = [:]
        var keys: [Bucket] = []
        keys.reserveCapacity(net.poles.count)
        for (position, pole) in net.poles.enumerated() {
            let key = Bucket(x: cell(pole.x), y: cell(pole.y), z: cell(pole.z))
            keys.append(key)
            buckets[key, default: []].append(position)
        }
        var parent = Array(net.poles.indices)
        func root(_ start: Int) -> Int {
            var node = start
            while parent[node] != node {
                parent[node] = parent[parent[node]]
                node = parent[node]
            }
            return node
        }
        for (position, pole) in net.poles.enumerated() {
            let near = neighbours(of: keys[position], in: buckets)
            for other in near where other > position && (net.poles[other] - pole).length <= tolerance {
                let a = root(position)
                let b = root(other)
                if a != b { parent[max(a, b)] = min(a, b) }
            }
        }
        var members: [Int: [Int]] = [:]
        for position in net.poles.indices { members[root(position), default: []].append(position) }
        var found: [PoleIndex: Set<PoleIndex>] = [:]
        for group in members.values where group.count > 1 {
            let indices = group.map { PoleIndex(i: $0 / net.vCount, j: $0 % net.vCount) }
            for index in indices { found[index] = Set(indices).subtracting([index]) }
        }
        return found
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
