import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport
import Observation

/// The Measure tool (measure spec, part A): clicks pick up to two faces, edges or corners of the shown parts and the session
/// reads their numbers (`MeasureReadings`), asks the kernel for the shortest distance between them, and draws what it knows over
/// the viewport. It is the viewport's tool, so a click on the model reaches it first and never selects a node. It makes no
/// command: it is not document state.
@MainActor
@Observable
final class MeasureSession: ViewportTool {
    /// The current measurement as it would be stored: one or two anchors that name what was picked without a scene.
    private(set) var anchors: [MeasureAnchor] = []
    /// The solid index each anchor was picked on, or last resolved on, in step with `anchors`: tags are shared between parts built
    /// from one feature, so the part stays the one the person clicked.
    private(set) var solidHints: [Int] = []
    /// The anchors resolved in the latest scene; always `anchors` read again after an edit.
    private(set) var picks: [MeasurePick] = []
    /// Some anchor no longer resolves in the scene (the part it named changed or went, or the section it stood on is off).
    private(set) var isLost = false
    private(set) var hover: MeasurePick?
    private(set) var readings: [MeasureReading] = []
    internal(set) var distance: ShapeDistance?
    /// A distance is being computed.
    internal(set) var isMeasuring = false
    /// The kernel's refusal of the last distance, in its words.
    internal(set) var problem: String?
    /// How the two faces of a single picked edge meet; `nil` for anything else, an edge that joins fewer than two faces, or while asking.
    internal(set) var continuity: EdgeContinuity?
    /// The kernel failed (other than by saying the edge has no two faces) to measure the picked edge's continuity.
    internal(set) var continuityFailed = false
    /// The overlay (hover and picks) changed: the app shows it again.
    @ObservationIgnored var overlayChanged: (@MainActor () -> Void)?
    /// The picks, the readings or the distance changed: the app shows the dimensions again.
    @ObservationIgnored var dimensionsChanged: (@MainActor () -> Void)?
    /// Takes a measurement the person leaves behind (a third click, `keepCurrent()`).
    @ObservationIgnored var keep: (@MainActor (KeptMeasurement) -> Void)?

    @ObservationIgnored private(set) weak var viewport: ViewportModel?
    @ObservationIgnored let kernel: any Kernel
    @ObservationIgnored var task: Task<Void, Never>?
    @ObservationIgnored var generation = 0
    /// The element last heard under the pointer; `pointerMoved` snaps it again as the pointer or the camera moves.
    @ObservationIgnored private var lastTarget: PickTarget?
    @ObservationIgnored private var hoverSolid: ObjectIdentifier?
    /// The scene as the app last described it: picks name its solids by position, and anchors resolve against it.
    @ObservationIgnored private var scene: MeasureScene
    /// The solids the picks stand on, to tell an edit that rebuilt one from a scene change that left it alone.
    @ObservationIgnored private var pickedSolids: [ObjectIdentifier] = []
    /// The full circles' centres of the pickable solids in `scene`, found once per scene.
    @ObservationIgnored private var circleCentres: [CircleCentre]?

    var solids: [Solid] { scene.solids }

    /// The mesh resolution behind the picks' approximate numbers in the latest scene, the coarsest of them; `nil` when no mesh made one.
    var meshResolution: Double? {
        picks.compactMap { MeasureResolver.meshResolution(of: $0, in: scene) }.max()
    }

    init(kernel: any Kernel, viewport: ViewportModel) {
        self.kernel = kernel
        self.viewport = viewport
        let items = viewport.items
        scene = MeasureScene(solids: items.map(\.solid), pickable: items.map { !$0.isGhost && !$0.isGuide }, parts: [],
                             plane: nil)
        // The viewport tells a tool nothing of a hover that began before it was set; the next pointer move snaps it.
        lastTarget = viewport.hovered
    }

    var offersSectionFromFace: Bool { true }

    // MARK: - Public surface

    /// Ends the session: a distance still being computed is dropped.
    func stop() {
        task?.cancel()
        task = nil
        generation += 1
        isMeasuring = false
    }

    /// Forgets the picks and the distance.
    func clear() {
        guard !anchors.isEmpty || !picks.isEmpty || distance != nil || problem != nil || isMeasuring || isLost else { return }
        anchors = []
        solidHints = []
        isLost = false
        setPicks([])
    }

    /// Hands the current measurement to `keep`, then forgets it. Nothing happens while an anchor is lost.
    func keepCurrent() {
        guard !anchors.isEmpty, !isLost else { return }
        keep?(KeptMeasurement(anchors: anchors))
        clear()
    }

    /// Waits until no distance is being computed.
    func waitForDistance() async {
        while isMeasuring, let running = task { await running.value }
    }

    /// The picked edges and corners, and the hovered edge or corner, as lines and points over the model.
    var overlay: ViewportOverlay {
        var overlay = ViewportOverlay()
        for pick in picks { add(pick, tint: .selected, to: &overlay) }
        if let hover, !picks.contains(hover) { add(hover, tint: .hovered, to: &overlay) }
        return overlay
    }

    func dimensions(style: DimensionStyle, units: DocumentUnits) -> [OverlayDimension] {
        MeasureDimensions.dimensions(for: picks, readings: readings, distance: distance, topologies: topologies(),
                                     style: style, units: units)
    }

    /// The scene changed (an edit, the section's plane or pieces): the anchors resolve again, and when the picks they give, or a
    /// solid under them, are not the ones measured, the numbers and the distance are made again. A pick that no longer resolves
    /// leaves the measurement lost until a later scene finds it.
    func sceneChanged(_ new: MeasureScene) {
        scene = new
        circleCentres = nil
        lastTarget = viewport?.hovered
        if let hover, !scene.solids.indices.contains(hover.solidIndex) || identity(of: hover) != hoverSolid {
            self.hover = nil
            bumpOverlay()
        }
        recompute()
    }

    // MARK: - ViewportTool

    func hoverChanged(_ target: PickTarget?, at point: ScreenPoint?, projector: ViewportProjector) {
        lastTarget = target
        updateHover(at: point, projector: projector)
    }

    func pointerMoved(to point: ScreenPoint?, modifiers: ViewportModifiers, projector: ViewportProjector) {
        updateHover(at: point, projector: projector)
    }

    func clicked(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool { false }

    func clickedModel(_ target: PickTarget?, at point: ScreenPoint, modifiers: ViewportModifiers,
                      projector: ViewportProjector) -> Bool {
        // The section's outline wins over the model behind it.
        let pick: MeasurePick?
        if let outline = sectionPick(at: point, projector: projector) ?? centrePick(at: point, target: target, projector: projector) {
            pick = outline
        } else if let target {
            pick = clickedPick(target, at: point, projector: projector)
        } else {
            clear()
            return true
        }
        // A ghost, a guide, a click that names nothing, or a pick no anchor can name does nothing.
        guard let pick, let anchor = MeasureResolver.anchor(for: pick, in: scene) else { return true }
        // A click first drops the anchors that no longer resolve, so none is kept, toggled or counted against the pair.
        if isLost {
            let found = anchors.indices.filter { MeasureResolver.resolve(anchors[$0], in: scene, preferring: solidHints[$0]) != nil }
            anchors = found.map { anchors[$0] }
            solidHints = found.map { solidHints[$0] }
        }
        // The same face on two parts is two picks: an anchor toggles off only on the part it was picked on.
        if let index = anchors.indices.first(where: { isSame(anchorAt: $0, as: anchor, pick: pick) }) {
            anchors.remove(at: index)
            solidHints.remove(at: index)
        } else if anchors.count >= 2 {
            keep?(KeptMeasurement(anchors: anchors))
            anchors = [anchor]
            solidHints = [pick.solidIndex]
        } else {
            anchors.append(anchor)
            solidHints.append(pick.solidIndex)
        }
        recompute()
        return true
    }

    func dragBegan(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool { false }
    func dragMoved(to point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {}
    func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {}

    // MARK: - Picking

    private func isPickable(_ target: PickTarget, allowingMesh: Bool = false) -> Bool {
        // The picks name the session's own solids; the live items only say whether the same solid is a ghost or a guide.
        guard let items = viewport?.items, items.indices.contains(target.solidIndex),
              solids.indices.contains(target.solidIndex) else { return false }
        let item = items[target.solidIndex]
        return item.solid === solids[target.solidIndex] && !item.isGhost && !item.isGuide
            && (allowingMesh || item.solid.displayedMesh == nil)
    }

    /// A click on the model: an exact face, edge or corner, or, on a mesh, the point of its surface under the click.
    private func clickedPick(_ target: PickTarget, at point: ScreenPoint, projector: ViewportProjector) -> MeasurePick? {
        guard isPickable(target, allowingMesh: true) else { return nil }
        if solids[target.solidIndex].displayedMesh != nil {
            return viewport?.surfacePoint(at: point, solidIndex: target.solidIndex).map {
                .meshPoint(solid: target.solidIndex, at: $0)
            }
        }
        return snapped(target, at: point, projector: projector)
    }

    private func snapped(_ target: PickTarget, at point: ScreenPoint, projector: ViewportProjector) -> MeasurePick? {
        guard let viewport, isPickable(target) else { return nil }
        let solid = solids[target.solidIndex]
        return MeasureSnap.pick(for: target, at: point, topology: solid.topology, mesh: viewport.displayMesh(of: solid),
                                screenPoint: { projector.screenPoint(of: $0) })
    }

    /// The section's outline piece within a few points of `point`, as a pick on the part it was cut from.
    private func sectionPick(at point: ScreenPoint, projector: ViewportProjector) -> MeasurePick? {
        guard scene.plane != nil, !scene.parts.isEmpty else { return nil }
        guard let hit = MeasureSectionPick.nearest(to: point, in: scene.parts, bounds: scene.sectionBounds,
                                                   screenPoint: { projector.screenPoint(of: $0) }) else { return nil }
        let part = scene.parts[hit.part]
        guard let index = scene.solids.indices.first(where: { scene.solids[$0] === part.solid && scene.pickable[$0] })
        else { return nil }
        let piece = part.section.pieces[hit.piece]
        return .sectionEdge(solid: index, piece: piece, at: MeasureResolver.midpoint(of: piece))
    }

    /// Whether the picked anchor at `index` is what `pick` (named by `anchor`) picks: the same anchor on the same part, or the
    /// same point of the same part (one vertex reached through two edges is one pick).
    private func isSame(anchorAt index: Int, as anchor: MeasureAnchor, pick: MeasurePick) -> Bool {
        if anchors[index] == anchor, solidHints[index] == pick.solidIndex { return true }
        guard case let .corner(solid, _, _, point) = pick, case .corner = anchors[index],
              case let .corner(otherSolid, _, _, other)? = MeasureResolver.resolve(anchors[index], in: scene,
                                                                                    preferring: solidHints[index])
        else { return false }
        return solid == otherSolid && (point - other).length < 1e-6
    }

    /// The centre of a full circle within reach of the pointer (`MeasureSnap.centre`), before any edge or face under it.
    /// Only circles of the solid under the pointer (`target`) count, or of every pickable solid when nothing is under it; a centre on
    /// the section's cut-away side is not there, and of two centres at one place the one nearer the camera wins.
    private func centrePick(at point: ScreenPoint, target: PickTarget?, projector: ViewportProjector) -> MeasurePick? {
        if circleCentres == nil {
            circleCentres = scene.solids.indices.flatMap { index -> [CircleCentre] in
                guard scene.pickable.indices.contains(index), scene.pickable[index],
                      scene.solids[index].displayedMesh == nil else { return [] }
                return MeasureSnap.circleCentres(of: scene.solids[index].topology, solid: index)
            }
        }
        let candidates = (circleCentres ?? []).filter { circle in
            (target.map { circle.solid == $0.solidIndex } ?? true) && viewport?.clip?.removes(circle.centre) != true
        }
        return MeasureSnap.centre(at: point, among: candidates, screenPoint: { projector.screenPoint(of: $0) },
                                  depth: { $0.dot(projector.pose.toEye) })
    }

    private func updateHover(at point: ScreenPoint?, projector: ViewportProjector) {
        var next: MeasurePick?
        if let point {
            next = sectionPick(at: point, projector: projector) ?? centrePick(at: point, target: lastTarget, projector: projector)
            if next == nil, let target = lastTarget { next = snapped(target, at: point, projector: projector) }
        }
        guard next != hover else { return }
        hover = next
        hoverSolid = next.flatMap { identity(of: $0) }
        bumpOverlay()
    }

    private func identity(of pick: MeasurePick) -> ObjectIdentifier? {
        solids.indices.contains(pick.solidIndex) ? ObjectIdentifier(solids[pick.solidIndex]) : nil
    }

    // MARK: - The measurement

    /// Resolves the anchors in the scene and, when the picks or a solid under them changed, measures again.
    private func recompute() {
        var resolved: [MeasurePick] = []
        for index in anchors.indices {
            guard let pick = MeasureResolver.resolve(anchors[index], in: scene, preferring: solidHints[index]) else { continue }
            solidHints[index] = pick.solidIndex
            resolved.append(pick)
        }
        let lost = resolved.count < anchors.count
        let involved = resolved.compactMap(identity(of:))
        guard resolved != picks || involved != pickedSolids || lost != isLost else { return }
        isLost = lost
        setPicks(resolved)
    }

    private func setPicks(_ new: [MeasurePick]) {
        task?.cancel()
        task = nil
        generation += 1
        picks = new
        pickedSolids = new.compactMap(identity(of:))
        distance = nil
        problem = nil
        continuity = nil
        continuityFailed = false
        isMeasuring = false
        readings = MeasureReadings.readings(for: new, topologies: topologies())
        if new.count == 2, !isLost { startDistance(new[0], new[1]) }
        if new.count == 1, !isLost, case let .edge(index, id) = new[0], solids.indices.contains(index) {
            startContinuity(solids[index], id)
        }
        bumpOverlay()
        dimensionsChanged?()
    }

    func bumpOverlay() {
        overlayChanged?()
    }

    private func topologies() -> [Int: Topology] {
        var result: [Int: Topology] = [:]
        for pick in picks where solids.indices.contains(pick.solidIndex) { result[pick.solidIndex] = solids[pick.solidIndex].topology }
        return result
    }
}
