import CreatorGeometry
import CreatorKernel
import Foundation

/// What a pick is for: the tool that takes it decides which things it accepts (plan R5).
public enum PickPurpose: Sendable {
    case dimension, holeCallout, centreMark, centreLine, leader
}

/// The model-plane shape a pick contributes to a dimension (model millimetres in the view plane).
public enum PickShape: Hashable, Sendable {
    case line(Vector2, Vector2)
    case circle(center: Vector2, radius: Double, isFull: Bool)
    case point(Vector2)
    /// A cylinder seen side on: a point on its axis, the axis's direction (unit) and its radius.
    case cylinder(axisPoint: Vector2, direction: Vector2, radius: Double)
}

/// A pick that was accepted: what to store and what it looks like on the view.
public struct PickedAnchor: Hashable, Sendable {
    public var target: AnchorTarget
    public var shape: PickShape

    public init(target: AnchorTarget, shape: PickShape) {
        self.target = target
        self.shape = shape
    }
}

/// Turns what a click found into an anchor, or says in a sentence why it can't be one (plan R3 and R5).
public enum DrawingPick {
    public static let isometricSentence = "Isometric views take notes and leaders, not dimensions."
    public static let noEdgeNameSentence = "This edge has no lasting name, so a dimension can't hold on to it."
    public static let sharedEdgeSentence = "This line's edge shares its name with other edges, so a dimension can't hold on to it."
    public static let notLineOrCircleSentence = "This edge isn't a straight line or a circle, so it can't be dimensioned here."
    public static let cornerSentence = "This corner can't be named; dimension the edge instead."
    public static let outlineOnlySentence = "Only a cylinder's outline can be dimensioned here."
    public static let noCylinderNameSentence = "This cylinder has no lasting name, so a dimension can't hold on to it."
    public static let sharedCylinderSentence = "This cylinder shares its name with other faces, so a dimension can't hold on to it."
    public static let lineSentence = """
        This edge isn't square to the view, so its length here would be foreshortened. \
        Dimension it in a view that sees it face on, or in an auxiliary view.
        """
    public static let circleSentence = """
        This circle isn't seen face on, so its size here would be foreshortened. \
        Dimension it in a view that looks along its axis.
        """
    public static let cylinderSentence = "This cylinder isn't seen side on, so its size here would be foreshortened."
    public static let holeSentence = "This circle isn't the edge of a plain, counterbored or countersunk hole."
    public static let holeCircleSentence = "A hole callout goes on a circle."
    public static let centreMarkSentence = "A centre mark goes on a circle."
    public static let centreLineSentence = "A centre line goes along a cylinder seen side on."

    // The brief fixes this signature: the click, the tool, the part's topology and the view's frame, mapping and kind.
    // swiftlint:disable:next function_parameter_count
    public static func anchor(
        for candidate: PickCandidate, click: Vector2, purpose: PickPurpose, topology: Topology, frame: ProjectionFrame,
        mapping: ViewMapping, isIsometric: Bool
    ) -> Result<PickedAnchor, DrawingRefusal> {
        if isIsometric, purpose != .leader { return .failure(DrawingRefusal(sentence: isometricSentence)) }
        let picker = Picker(topology: topology, frame: frame, mapping: mapping, purpose: purpose, click: click)
        return picker.anchor(for: candidate)
    }

    /// Whether the unit vectors are the same line, to 1e-9.
    static func isParallel(_ a: Vector2, _ b: Vector2) -> Bool {
        abs(a.x * b.y - a.y * b.x) <= 1e-9 * a.length * b.length
    }
}

extension DrawingPick {
    struct Picker {
        let topology: Topology
        let frame: ProjectionFrame
        let mapping: ViewMapping
        let purpose: PickPurpose
        let click: Vector2

        func anchor(for candidate: PickCandidate) -> Result<PickedAnchor, DrawingRefusal> {
            switch candidate {
            case .edge(let id, _): return topology.edge(id).map(edge) ?? .failure(refusal(noEdgeNameSentence))
            case .corner(let id, let point):
                guard purpose == .dimension || purpose == .leader else { return .failure(wrong()) }
                return topology.edge(id).map { corner($0, at: point) } ?? .failure(refusal(noEdgeNameSentence))
            case .centre(let id, _):
                guard let edge = topology.edge(id) else { return .failure(refusal(noEdgeNameSentence)) }
                return purpose == .dimension || purpose == .leader ? centre(edge) : self.edge(edge)
            case .outline(let id, _): return outline(id)
            }
        }

        func refusal(_ sentence: String) -> DrawingRefusal { DrawingRefusal(sentence: sentence) }

        /// The refusal of a tool that takes none of what was clicked.
        func wrong() -> DrawingRefusal {
            switch purpose {
            case .holeCallout: refusal(holeCircleSentence)
            case .centreMark: refusal(centreMarkSentence)
            case .centreLine: refusal(centreLineSentence)
            case .dimension, .leader: refusal(outlineOnlySentence)
            }
        }

        // MARK: Edges

        /// The pick that names `edge` (plan R3): both sides of its key lasting, the key forming exactly one run.
        func name(_ edge: EdgeInfo) -> Result<EdgePick, DrawingRefusal> {
            guard let key = topology.key(of: edge), AnchorNaming.isLasting(key.first), AnchorNaming.isLasting(key.second) else {
                return .failure(refusal(noEdgeNameSentence))
            }
            let matches = topology.edges(matching: key)
            guard matches.contains(where: { $0.id == edge.id }) else { return .failure(refusal(noEdgeNameSentence)) }
            guard Topology.runCount(matches) == 1 else { return .failure(refusal(sharedEdgeSentence)) }
            return .success(EdgePick(key: key, matchCount: matches.count, runCount: matches.count > 1 ? 1 : nil))
        }

        func held(_ target: AnchorTarget) -> Result<AnchorGeometry, DrawingRefusal> {
            switch DrawingAnchorResolver.resolve(target, in: topology, frame: frame) {
            case .held(let geometry, _, _): return .success(geometry)
            case .lost(let reason): return .failure(refusal(reason.sentence))
            }
        }

        func edge(_ edge: EdgeInfo) -> Result<PickedAnchor, DrawingRefusal> {
            let pick: EdgePick
            switch name(edge) {
            case .failure(let refused): return .failure(refused)
            case .success(let named): pick = named
            }
            let target = AnchorTarget.edge(pick)
            let geometry: AnchorGeometry
            switch held(target) {
            case .failure(let refused): return .failure(refused)
            case .success(let found): geometry = found
            }
            if purpose == .leader { return .success(PickedAnchor(target: target, shape: shape(of: geometry))) }
            if let refused = refuse(geometry) { return .failure(refused) }
            if purpose == .holeCallout, case .failure(let refused) = readHole(target) { return .failure(refused) }
            return .success(PickedAnchor(target: target, shape: shape(of: geometry)))
        }

        /// R5's rules and each tool's own, for a dimensioned, called out or marked edge.
        private func refuse(_ geometry: AnchorGeometry) -> DrawingRefusal? {
            switch (purpose, geometry) {
            case (.centreLine, _): return refusal(centreLineSentence)
            case (.holeCallout, .circle(_, let axis, _, let sweep)):
                guard sweep >= 2 * .pi - 1e-9 else { return refusal(holeCircleSentence) }
                return isFaceOn(axis) ? nil : refusal(circleSentence)
            case (.holeCallout, _): return refusal(holeCircleSentence)
            case (.centreMark, .circle(_, let axis, _, _)): return isFaceOn(axis) ? nil : refusal(circleSentence)
            case (.centreMark, _): return refusal(centreMarkSentence)
            case (_, .segment(let a, let b)):
                let along = b - a
                return abs(along.dot(frame.direction)) <= 1e-9 * along.length ? nil : refusal(lineSentence)
            case (_, .circle(_, let axis, _, _)): return isFaceOn(axis) ? nil : refusal(circleSentence)
            default: return refusal(notLineOrCircleSentence)
            }
        }

        func isFaceOn(_ axis: Vector3) -> Bool { abs(axis.dot(frame.direction)) >= 1 - 1e-9 }

        private func readHole(_ target: AnchorTarget) -> Result<Void, DrawingRefusal> {
            switch HoleReader.read(target, in: topology, frame: frame) {
            case .hole: return .success(())
            case .notAHole: return .failure(refusal(holeSentence))
            case .lost(let reason): return .failure(refusal(reason.sentence))
            }
        }

        func shape(of geometry: AnchorGeometry) -> PickShape {
            switch geometry {
            case .segment(let a, let b): return .line(frame.place(a), frame.place(b))
            case .circle(let center, _, let radius, let sweep):
                return .circle(center: frame.place(center), radius: radius, isFull: sweep >= 2 * .pi - 1e-9)
            case .point(let p): return .point(frame.place(p))
            case .cylinder(let axisPoint, let axis, let radius, _):
                let flat = frame.place(axis)
                let unit = flat.length > 0 ? flat * (1 / flat.length) : flat
                return .cylinder(axisPoint: frame.place(axisPoint), direction: unit, radius: radius)
            case .other(let midpoint): return .point(frame.place(midpoint))
            }
        }

        // MARK: Centres

        func centre(_ edge: EdgeInfo) -> Result<PickedAnchor, DrawingRefusal> {
            let pick: EdgePick
            switch name(edge) {
            case .failure(let refused): return .failure(refused)
            case .success(let named): pick = named
            }
            let circle: AnchorGeometry
            switch held(.edge(pick)) {
            case .failure(let refused): return .failure(refused)
            case .success(let found): circle = found
            }
            guard case .circle(let center, let axis, _, _) = circle else { return .failure(refusal(notLineOrCircleSentence)) }
            if purpose == .dimension, !isFaceOn(axis) { return .failure(refusal(circleSentence)) }
            return .success(PickedAnchor(target: .centre(pick), shape: .point(frame.place(center))))
        }
    }
}
