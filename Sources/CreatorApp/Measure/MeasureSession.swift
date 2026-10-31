import CreatorGeometry
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
    private(set) var picks: [MeasurePick] = []
    private(set) var hover: MeasurePick?
    private(set) var readings: [MeasureReading] = []
    private(set) var distance: ShapeDistance?
    /// A distance is being computed.
    private(set) var isMeasuring = false
    /// The kernel's refusal of the last distance, in its words.
    private(set) var problem: String?
    /// Bumps on every change the scene must redraw.
    private(set) var revision = 0

    /// The overlay (hover and picks) changed: the app shows it again.
    @ObservationIgnored var overlayChanged: (@MainActor () -> Void)?
    /// The picks, the readings or the distance changed: the app shows the dimensions again.
    @ObservationIgnored var dimensionsChanged: (@MainActor () -> Void)?

    @ObservationIgnored private weak var viewport: ViewportModel?
    @ObservationIgnored private let kernel: any Kernel
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    /// The element last heard under the pointer; `pointerMoved` snaps it again as the pointer or the camera moves.
    @ObservationIgnored private var lastTarget: PickTarget?
    /// The solids the scene shows now, by position; picks name them by that position, so a change of any clears the measurement.
    @ObservationIgnored private var solids: [Solid] = []

    init(kernel: any Kernel, viewport: ViewportModel) {
        self.kernel = kernel
        self.viewport = viewport
        solids = viewport.items.map(\.solid)
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
        guard !picks.isEmpty || distance != nil || problem != nil || isMeasuring else { return }
        setPicks([])
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

    /// The scene changed: when its solids are not the ones the picks name, the measurement ends (part A does not follow edits).
    func sceneChanged(_ items: [ViewportItem]) {
        let now = items.map(\.solid)
        guard now.count != solids.count || zip(now, solids).contains(where: { $0 !== $1 }) else { return }
        solids = now
        lastTarget = nil
        if hover != nil {
            hover = nil
            bumpOverlay()
        }
        clear()
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
        guard let target else {
            clear()
            return true
        }
        // A ghost, a guide or a mesh is no part of the model to measure: the click does nothing.
        guard isPickable(target), let pick = snapped(target, at: point, projector: projector) else { return true }
        if let index = picks.firstIndex(of: pick) {
            var rest = picks
            rest.remove(at: index)
            setPicks(rest)
        } else {
            setPicks(picks.count >= 2 ? [pick] : picks + [pick])
        }
        return true
    }

    func dragBegan(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) -> Bool { false }
    func dragMoved(to point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {}
    func dragEnded(at point: ScreenPoint, modifiers: ViewportModifiers, projector: ViewportProjector) {}

    // MARK: - Picking

    private func isPickable(_ target: PickTarget) -> Bool {
        // The picks name the session's own solids; the live items only say whether the same solid is a ghost, a guide or a mesh.
        guard let items = viewport?.items, items.indices.contains(target.solidIndex),
              solids.indices.contains(target.solidIndex) else { return false }
        let item = items[target.solidIndex]
        return item.solid === solids[target.solidIndex] && !item.isGhost && !item.isGuide && item.solid.displayedMesh == nil
    }

    private func snapped(_ target: PickTarget, at point: ScreenPoint, projector: ViewportProjector) -> MeasurePick? {
        guard let viewport, isPickable(target) else { return nil }
        let solid = solids[target.solidIndex]
        return MeasureSnap.pick(for: target, at: point, topology: solid.topology, mesh: viewport.displayMesh(of: solid),
                                screenPoint: { projector.screenPoint(of: $0) })
    }

    private func updateHover(at point: ScreenPoint?, projector: ViewportProjector) {
        var next: MeasurePick?
        if let point, let target = lastTarget { next = snapped(target, at: point, projector: projector) }
        guard next != hover else { return }
        hover = next
        bumpOverlay()
    }

    // MARK: - The measurement

    private func setPicks(_ new: [MeasurePick]) {
        task?.cancel()
        task = nil
        generation += 1
        picks = new
        distance = nil
        problem = nil
        isMeasuring = false
        readings = MeasureReadings.readings(for: new, topologies: topologies())
        if new.count == 2 { startDistance(new[0], new[1]) }
        bumpOverlay()
        dimensionsChanged?()
    }

    private func startDistance(_ first: MeasurePick, _ second: MeasurePick) {
        let generation = generation
        guard let a = first.element(in: solids), let b = second.element(in: solids) else { return }
        isMeasuring = true
        task = Task { [weak self, kernel] in
            do {
                let found = try await kernel.shortestDistance(between: a, and: b)
                self?.landed(found, generation: generation)
            } catch is CancellationError {
                return
            } catch let error as KernelError {
                self?.refused(error.userMessage, generation: generation)
            } catch {
                self?.refused(error.localizedDescription, generation: generation)
            }
        }
    }

    /// A distance for an older pair than the picks now are is dropped.
    private func landed(_ found: ShapeDistance, generation: Int) {
        guard generation == self.generation else { return }
        distance = found
        isMeasuring = false
        bumpOverlay()
        dimensionsChanged?()
    }

    private func refused(_ message: String, generation: Int) {
        guard generation == self.generation else { return }
        problem = message
        isMeasuring = false
        bumpOverlay()
    }

    private func bumpOverlay() {
        revision += 1
        overlayChanged?()
    }

    private func topologies() -> [Int: Topology] {
        var result: [Int: Topology] = [:]
        for pick in picks where solids.indices.contains(pick.solidIndex) { result[pick.solidIndex] = solids[pick.solidIndex].topology }
        return result
    }

    // MARK: - Drawing

    private func add(_ pick: MeasurePick, tint: OverlayTint, to overlay: inout ViewportOverlay) {
        switch pick {
        case .face: break
        case let .edge(solid, id):
            let path = edgePath(solid, id)
            for (a, b) in zip(path, path.dropFirst()) { overlay.lines.append(OverlayLine(a, b, tint: tint, width: 3)) }
        case let .corner(_, _, _, point):
            overlay.points.append(OverlayPoint(point, tint: tint, size: 10))
        }
    }

    /// The polyline the viewport draws an edge along, else (a display mesh without one) the straight line between its ends.
    private func edgePath(_ solidIndex: Int, _ id: EdgeID) -> [Vector3] {
        guard solids.indices.contains(solidIndex) else { return [] }
        let solid = solids[solidIndex]
        if let line = viewport?.displayMesh(of: solid)?.edgePolylines[id], line.count >= 2 { return line }
        if let ends = solid.topology.edge(id)?.curve?.ends, ends.count == 2 { return ends }
        return []
    }
}
