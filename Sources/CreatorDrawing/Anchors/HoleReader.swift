import CreatorGeometry
import CreatorKernel
import Foundation

/// What a picked circle turned out to be (plan R12).
public enum HoleReading: Hashable, Sendable {
    /// A hole, with the picked circle's centre, axis and radius (not the mouth's).
    case hole(HoleShape, center: Vector3, axis: Vector3, radius: Double)
    case notAHole
    case lost(LostReason)
}

/// Reads a plain, counterbored or countersunk hole from the topology around a picked circle (plan R12). It works on
/// `Topology` alone: faces' kinds, the circles on their edges and the planes' normals.
public enum HoleReader {
    private static let axisParallel = 1 - 1e-9
    private static let onAxis = 1e-6
    private static let sameRadius = 1e-6

    public static func read(_ target: AnchorTarget, in topology: Topology, frame: ProjectionFrame) -> HoleReading {
        let pick: EdgePick
        switch target {
        case .edge(let found), .centre(let found): pick = found
        default: return .notAHole
        }
        switch DrawingAnchorResolver.resolve(.edge(pick), in: topology, frame: frame) {
        case .lost(let reason): return .lost(reason)
        case .held(.circle(let center, let axis, let radius, _), let edges, _):
            guard abs(axis.dot(frame.direction)) >= axisParallel else { return .lost(.foreshortened) }
            guard let first = edges.first.flatMap({ topology.edge($0) }) else { return .lost(.missing) }
            guard let shape = Reader(topology: topology, axis: axis, origin: center).shape(startingAt: first, radius: radius) else {
                return .notAHole
            }
            return .hole(shape, center: center, axis: axis, radius: radius)
        case .held: return .notAHole
        }
    }

    /// A full circle edge on the hole's axis.
    private struct Ring {
        var edge: EdgeInfo
        var center: Vector3
        var radius: Double
    }

    /// The hole's own wall and where it starts, beneath a countersink or a counterbore if there is one.
    private struct Entry {
        var wall: FaceInfo
        var start: Ring
        var counterbore: HoleShape.Counterbore?
        var countersink: HoleShape.Countersink?
        var floorDepth = 0.0
    }

    private struct Reader {
        let topology: Topology
        let axis: Vector3
        let origin: Vector3

        /// Distance along the axis from `origin`, positive in the direction the hole runs.
        func depth(of point: Vector3, running direction: Vector3) -> Double { (point - origin).dot(direction) }

        func isOnAxis(_ point: Vector3) -> Bool {
            let offset = point - origin
            return (offset - axis * offset.dot(axis)).length <= HoleReader.onAxis
        }

        func isParallel(_ other: Vector3?) -> Bool {
            guard let unit = other?.normalized else { return false }
            return abs(unit.dot(axis)) >= HoleReader.axisParallel
        }

        func ring(_ edge: EdgeInfo) -> Ring? {
            guard !edge.isSeam, case .circle(let center, let circleAxis, let radius, _, _)? = edge.curve else { return nil }
            guard isParallel(circleAxis), isOnAxis(center) else { return nil }
            return Ring(edge: edge, center: center, radius: radius)
        }

        func rings(of face: FaceInfo) -> [Ring] { topology.edges(of: face.id).compactMap(ring) }

        func isWall(_ face: FaceInfo) -> Bool {
            (face.kind == .cylinder || face.kind == .cone) && isParallel(face.normal)
        }

        func isFlat(_ face: FaceInfo) -> Bool { face.kind == .plane && isParallel(face.normal) }

        /// The two faces of a circle: its wall and its plane, or nil.
        func sides(of ring: Ring) -> (wall: FaceInfo, plane: FaceInfo)? {
            let faces = Set(ring.edge.faces).compactMap { topology.face($0) }
            guard faces.count == 2 else { return nil }
            if let wall = faces.first(where: isWall), let plane = faces.first(where: isFlat) { return (wall, plane) }
            return nil
        }

        func face(across ring: Ring, from face: FaceInfo) -> FaceInfo? {
            ring.edge.faces.first { $0 != face.id }.flatMap { topology.face($0) }
        }

        /// The mouth: from a circle on a plane, step out over larger coaxial circles on that plane to the far end of the wall
        /// they belong to, until the plane has none.
        func mouth(from start: Ring) -> (ring: Ring, wall: FaceInfo, plane: FaceInfo)? {
            var current = start
            for _ in 0..<16 {
                guard let (wall, plane) = sides(of: current) else { return nil }
                let larger = rings(of: plane)
                    .filter { $0.radius > current.radius + HoleReader.sameRadius && $0.edge.id != current.edge.id }
                    .sorted { $0.radius < $1.radius }
                guard let step = larger.first else { return (current, wall, plane) }
                guard let outerWall = face(across: step, from: plane), isWall(outerWall) else { return nil }
                // The step's wall must rise out of this plane, on the side its normal points to.
                let outward = plane.normal?.normalized ?? axis
                guard (outerWall.centroid - step.center).dot(outward) > 0 else { return nil }
                let stepDepth = depth(of: step.center, running: outward)
                let others = rings(of: outerWall).filter { abs(depth(of: $0.center, running: outward) - stepDepth) > 1e-6 }
                guard let far = others.max(by: { depth(of: $0.center, running: outward) < depth(of: $1.center, running: outward) })
                else { return nil }
                current = far
            }
            return nil
        }

        func shape(startingAt picked: EdgeInfo, radius: Double) -> HoleShape? {
            guard let start = ring(picked), let (mouth, wall, plane) = mouth(from: start) else { return nil }
            guard let normal = plane.normal?.normalized else { return nil }
            // A mouth is open: the plane has more than the circle on it, and the wall runs into the material.
            let planeEdges = topology.edges(of: plane.id).filter { !$0.isSeam }
            guard planeEdges.contains(where: { $0.id != mouth.edge.id && ring($0)?.radius != mouth.radius }) else { return nil }
            guard (wall.centroid - mouth.center).dot(normal) < 0 else { return nil }
            let down = -normal
            guard let entry = entry(mouth: mouth, wall: wall, down: down) else { return nil }
            let holeFar = rings(of: entry.wall).first {
                (($0.center - mouth.center).dot(down)) > (entry.start.center - mouth.center).dot(down) + 1e-9
            }
            let depth = blindDepth(of: entry.wall, far: holeFar, down: down, from: mouth.center).map { $0 - entry.floorDepth }
            return HoleShape(
                diameter: 2 * entry.start.radius, depth: depth, counterbore: entry.counterbore, countersink: entry.countersink)
        }

        private func entry(mouth: Ring, wall: FaceInfo, down: Vector3) -> Entry? {
            func at(_ point: Vector3) -> Double { (point - mouth.center).dot(down) }
            if wall.kind == .cone {
                guard let inner = rings(of: wall).first(where: { at($0.center) > 1e-9 && $0.radius < mouth.radius }) else { return nil }
                guard let next = face(across: inner, from: wall), next.kind == .cylinder, isWall(next) else { return nil }
                let angle = 2 * atan((mouth.radius - inner.radius) / at(inner.center))
                return Entry(wall: next, start: inner, countersink: .init(diameter: 2 * mouth.radius, angle: angle))
            }
            guard let far = rings(of: wall).first(where: { at($0.center) > 1e-9 }), let end = face(across: far, from: wall) else {
                return nil
            }
            let facesMouth = (end.normal?.normalized ?? down).dot(down) < 0
            let smaller = rings(of: end).filter { $0.edge.id != far.edge.id && $0.radius < far.radius - HoleReader.sameRadius }
            guard isFlat(end), facesMouth, let step = smaller.max(by: { $0.radius < $1.radius }) else {
                return Entry(wall: wall, start: mouth)
            }
            // A counterbore floor: a plane annulus round a smaller coaxial circle, with the hole's own wall beneath it.
            guard let next = face(across: step, from: end), next.kind == .cylinder, isWall(next) else { return nil }
            let floor = at(far.center)
            return Entry(
                wall: next, start: step, counterbore: .init(diameter: 2 * mouth.radius, depth: floor), floorDepth: floor)
        }

        /// The distance from the mouth plane to the hole's far end when that end is blind (a flat floor or a drill point), else nil.
        func blindDepth(of wall: FaceInfo, far: Ring?, down: Vector3, from top: Vector3) -> Double? {
            guard let far else { return nil }
            let distance = (far.center - top).dot(down)
            guard let end = face(across: far, from: wall) else { return nil }
            let onlyThisCircle = topology.edges(of: end.id).filter { !$0.isSeam }.allSatisfy { $0.id == far.edge.id }
            if end.kind == .plane, onlyThisCircle { return distance }
            if end.kind == .cone, isWall(end) {
                // A drill point narrows to an apex or a smaller disc; a cone that widens is an exit.
                let others = rings(of: end).filter { $0.edge.id != far.edge.id }
                if others.allSatisfy({ $0.radius < far.radius - HoleReader.sameRadius }) { return distance }
            }
            return nil
        }
    }
}
