import CreatorGeometry
import CreatorKernel
import Foundation

/// What a pick is for: the tool that takes it decides which things it accepts (plan R5).
public enum PickPurpose: Sendable {
    case dimension, holeCallout, centreMark, centreLine, leader
    /// DR-5's balloon (plan R4, R16): takes what a leader takes, in any view, worded for balloons.
    case balloon
    /// DR-4's symbols (plan R2): a datum feature symbol, a feature control frame and a surface texture symbol.
    case datum, frame, surface

    /// Whether the pick is for a symbol, which takes slanted lines and words its refusals for symbols (plan R2, R20).
    public var isSymbol: Bool {
        switch self {
        case .datum, .frame, .surface: true
        default: false
        }
    }

    /// The purpose that picks for `symbol`, also the one a re-attach click uses.
    public init(symbol: SymbolKind) {
        switch symbol {
        case .datum: self = .datum
        case .frame: self = .frame
        case .surface: self = .surface
        }
    }
}

/// The sentences a picker refuses with, by what it picks for (plan R20): DR-2's and DR-3's purposes keep their own words.
struct PickWording {
    let noEdgeName: String
    let sharedEdge: String
    let noCylinderName: String
    let sharedCylinder: String
    let cylinder: String

    static let dimensions = PickWording(
        noEdgeName: DrawingPick.noEdgeNameSentence, sharedEdge: DrawingPick.sharedEdgeSentence,
        noCylinderName: DrawingPick.noCylinderNameSentence, sharedCylinder: DrawingPick.sharedCylinderSentence,
        cylinder: DrawingPick.cylinderSentence)
    static let symbols = PickWording(
        noEdgeName: DrawingPick.symbolNoEdgeNameSentence, sharedEdge: DrawingPick.symbolSharedEdgeSentence,
        noCylinderName: DrawingPick.symbolNoCylinderNameSentence, sharedCylinder: DrawingPick.symbolSharedCylinderSentence,
        cylinder: DrawingPick.symbolCylinderSentence)

    static let balloons = PickWording(
        noEdgeName: DrawingPick.balloonNoEdgeNameSentence, sharedEdge: DrawingPick.balloonSharedEdgeSentence,
        noCylinderName: DrawingPick.balloonNoCylinderNameSentence, sharedCylinder: DrawingPick.balloonSharedCylinderSentence,
        cylinder: DrawingPick.cylinderSentence)

    static func of(_ purpose: PickPurpose) -> PickWording {
        if purpose == .balloon { return .balloons }
        return purpose.isSymbol ? .symbols : .dimensions
    }
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
    /// How far along the view direction a point pick lies (a corner or a centre), so two points at different depths can be refused an
    /// aligned dimension at the pick (plan R8); nil for a pick with no one place.
    public var depth: Double?

    public init(target: AnchorTarget, shape: PickShape, depth: Double? = nil) {
        self.target = target
        self.shape = shape
        self.depth = depth
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
    public static let holeSentence = "This circle isn't the mouth of a plain, counterbored or countersunk hole."
    public static let holeCircleSentence = "A hole callout goes on a circle."
    public static let centreMarkSentence = "A centre mark goes on a circle."
    public static let centreLineSentence = "A centre line goes along a cylinder seen side on."

    // DR-4 (plan R2, R20).
    public static let symbolIsometricSentence = "Isometric views take notes and leaders, not datum, tolerance or surface symbols."
    public static let datumCircleSentence = "A datum symbol stands on a straight line of a view or on a dimension."
    public static let surfaceCircleSentence = "A surface symbol stands on a straight line of a view."
    public static let symbolNoEdgeNameSentence = "This edge has no lasting name, so a symbol can't hold on to it."
    public static let symbolSharedEdgeSentence = "This line's edge shares its name with other edges, so a symbol can't hold on to it."
    public static let symbolNoCylinderNameSentence = "This cylinder has no lasting name, so a symbol can't hold on to it."
    public static let symbolSharedCylinderSentence = "This cylinder shares its name with other faces, so a symbol can't hold on to it."
    public static let symbolCylinderSentence = "This cylinder isn't seen side on, so it has no outline here for a symbol to stand on."
    public static let symbolEndOnSentence = "This edge is seen end on here, so a symbol can't stand on it."
    public static let symbolCircleSentence =
        "This circle isn't seen face on here; point the frame at it in a view that looks along its axis."
    public static let symbolCurveSentence = "This edge isn't a straight line or a circle, so a symbol can't stand on it here."

    // DR-5 (plan R16).
    public static let balloonNoEdgeNameSentence = "This edge has no lasting name, so a balloon can't hold on to it."
    public static let balloonSharedEdgeSentence = "This line's edge shares its name with other edges, so a balloon can't hold on to it."
    public static let balloonNoCylinderNameSentence = "This cylinder has no lasting name, so a balloon can't hold on to it."
    public static let balloonSharedCylinderSentence = "This cylinder shares its name with other faces, so a balloon can't hold on to it."

    // The brief fixes this signature: the click, the tool, the part's topology and the view's frame, mapping and kind.
    // swiftlint:disable:next function_parameter_count
    public static func anchor(
        for candidate: PickCandidate, click: Vector2, purpose: PickPurpose, topology: Topology, frame: ProjectionFrame,
        mapping: ViewMapping, isIsometric: Bool, parts: [PartSpan]?
    ) -> Result<PickedAnchor, DrawingRefusal> {
        if isIsometric, purpose != .leader, purpose != .balloon {
            return .failure(DrawingRefusal(sentence: purpose.isSymbol ? symbolIsometricSentence : isometricSentence))
        }
        guard let parts else {
            return Picker(topology: topology, frame: frame, mapping: mapping, purpose: purpose, click: click).anchor(for: candidate)
        }
        // An assembly view (R3): the pick is named and judged inside the part its line lies on, then wrapped with that part.
        guard let span = span(of: candidate, in: topology, parts: parts) else {
            return .failure(DrawingRefusal(sentence: freeCurveSentence(for: purpose)))
        }
        let scoped = topology.restricted(toFaces: span.faces)
        let picker = Picker(topology: scoped, frame: frame, mapping: mapping, purpose: purpose, click: click)
        return picker.anchor(for: candidate).map {
            PickedAnchor(target: .onPart(span.output, $0.target), shape: $0.shape, depth: $0.depth)
        }
    }

    /// The span holding the face the candidate's line lies on, or nil for a line on no part (a curve).
    private static func span(of candidate: PickCandidate, in topology: Topology, parts: [PartSpan]) -> PartSpan? {
        let face: FaceID?
        switch candidate {
        case .edge(let id, _), .corner(let id, _), .centre(let id, _): face = topology.edge(id)?.faces.first
        case .outline(let id, _): face = id
        }
        guard let face, let position = topology.faces.firstIndex(where: { $0.id == face }) else { return nil }
        return parts.span(containingFace: position)
    }

    static func freeCurveSentence(for purpose: PickPurpose?) -> String {
        switch purpose {
        case .balloon?: balloonFreeCurveSentence
        case let found? where found.isSymbol: symbolFreeCurveSentence
        default: DrawingPick.freeCurveSentence
        }
    }

    /// Whether a line with model direction `along` is seen end on in a view looking along `direction` (plan R2): the one test
    /// that refuses a symbol at the pick and loses it afterwards, so an accepted pick is never lost at once.
    static func isSeenEndOn(_ along: Vector3, direction: Vector3) -> Bool {
        (along - direction * along.dot(direction)).length <= 1e-9 * along.length
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

        var wording: PickWording { PickWording.of(purpose) }

        /// A note's leader and a balloon take any lasting edge, a corner's edge, a circle or a cylinder's outline.
        var takesLeaders: Bool { purpose == .leader || purpose == .balloon }

        func anchor(for candidate: PickCandidate) -> Result<PickedAnchor, DrawingRefusal> {
            switch candidate {
            case .edge(let id, _): return topology.edge(id).map(edge) ?? .failure(refusal(wording.noEdgeName))
            case .corner(let id, let point):
                // A symbol picks the corner's edge, as DR-3's auxiliary views do.
                if purpose.isSymbol { return topology.edge(id).map(edge) ?? .failure(refusal(wording.noEdgeName)) }
                guard purpose == .dimension || takesLeaders else { return .failure(wrong()) }
                return topology.edge(id).map { corner($0, at: point) } ?? .failure(refusal(wording.noEdgeName))
            case .centre(let id, _):
                guard let edge = topology.edge(id) else { return .failure(refusal(wording.noEdgeName)) }
                return purpose == .dimension || takesLeaders ? centre(edge) : self.edge(edge)
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
            case .dimension, .leader, .balloon: refusal(outlineOnlySentence)
            case .datum: refusal(datumCircleSentence)
            case .surface: refusal(surfaceCircleSentence)
            case .frame: refusal(symbolCurveSentence)
            }
        }

        // MARK: Edges

        /// The pick that names `edge` (plan R3): both sides of its key lasting, the key forming exactly one run.
        func name(_ edge: EdgeInfo) -> Result<EdgePick, DrawingRefusal> {
            guard let key = topology.key(of: edge), AnchorNaming.isLasting(key.first), AnchorNaming.isLasting(key.second) else {
                return .failure(refusal(wording.noEdgeName))
            }
            let matches = topology.edges(matching: key)
            guard matches.contains(where: { $0.id == edge.id }) else { return .failure(refusal(wording.noEdgeName)) }
            guard Topology.runCount(matches) == 1 else { return .failure(refusal(wording.sharedEdge)) }
            return .success(EdgePick(key: key, matchCount: matches.count, runCount: matches.count > 1 ? 1 : nil))
        }

        func held(_ target: AnchorTarget) -> Result<AnchorGeometry, DrawingRefusal> {
            switch DrawingAnchorResolver.resolve(target, in: topology, frame: frame, parts: []) {
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
            if takesLeaders { return .success(PickedAnchor(target: target, shape: shape(of: geometry))) }
            if purpose.isSymbol {
                if let refused = refuseSymbol(geometry) { return .failure(refused) }
                return .success(PickedAnchor(target: target, shape: shape(of: geometry)))
            }
            if let refused = refuse(geometry) { return .failure(refused) }
            if purpose == .holeCallout, case .failure(let refused) = readHole(target) { return .failure(refused) }
            // A line square to the view lies at one depth all along (plan R8).
            var depth: Double?
            if case .segment(let start, _) = geometry { depth = start.dot(frame.direction) }
            return .success(PickedAnchor(target: target, shape: shape(of: geometry), depth: depth))
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

        /// R2's rules for a symbol: any straight edge not seen end on, a face-on circle for a frame, nothing free-form.
        private func refuseSymbol(_ geometry: AnchorGeometry) -> DrawingRefusal? {
            switch geometry {
            case .segment(let a, let b):
                return DrawingPick.isSeenEndOn(b - a, direction: frame.direction) ? refusal(symbolEndOnSentence) : nil
            case .circle(_, let axis, _, _):
                switch purpose {
                case .datum: return refusal(datumCircleSentence)
                case .surface: return refusal(surfaceCircleSentence)
                default: return isFaceOn(axis) ? nil : refusal(symbolCircleSentence)
                }
            default:
                switch purpose {
                case .datum: return refusal(datumCircleSentence)
                case .surface: return refusal(surfaceCircleSentence)
                default: return refusal(symbolCurveSentence)
                }
            }
        }

        func isFaceOn(_ axis: Vector3) -> Bool { abs(axis.dot(frame.direction)) >= 1 - 1e-9 }

        private func readHole(_ target: AnchorTarget) -> Result<Void, DrawingRefusal> {
            switch HoleReader.read(target, in: topology, frame: frame, parts: []) {
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
            return .success(PickedAnchor(target: .centre(pick), shape: .point(frame.place(center)), depth: center.dot(frame.direction)))
        }
    }
}
