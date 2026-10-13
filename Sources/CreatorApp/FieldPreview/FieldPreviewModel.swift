import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorViewport
import Observation

/// The field preview (fields spec §6): the tint on the shown parts and the slice plane through them. It follows one field at a
/// time (`follow(_:)`), samples it off the main actor, and keeps the old tint and slice until the new ones are ready. Its
/// toggles and the slice's offset are view state in memory, never saved, never an undo step. `AppModel` feeds it from
/// `refreshScene()` and reads it back into the scene (`FieldPreviewModel+Scene`).
@MainActor
@Observable
final class FieldPreviewModel {
    static let sliceHandleID = "field-slice"

    /// Bumped by every change a view or the scene might draw; `AppModel` observes only this.
    private(set) var revision = 0
    private(set) var node: NodeID?
    private(set) var field: Field?
    private(set) var bounds: BoundingBox?
    /// The legend's "0…1" toggle.
    private(set) var usesUnitRange = false
    /// Where the slice is, and how far along its normal it has been moved.
    private(set) var choice = SliceChoice.hidden
    private(set) var offset = 0.0
    private(set) var tints: [ObjectIdentifier: SolidTint] = [:]
    private(set) var grid: SliceGrid?
    /// The kernel's words when the tint's last sampling failed, and when the slice's did. Each is cleared only by its own
    /// sampling (starting or succeeding), so one succeeding never hides the other's explanation.
    private(set) var tintFailure: String?
    private(set) var sliceFailure: String?
    private var tintRunning = false
    private var sliceRunning = false

    @ObservationIgnored private let kernel: any Kernel
    @ObservationIgnored private let distances: FieldDistanceCache?
    @ObservationIgnored private let vertexLimit: Int
    @ObservationIgnored private let meshes: @MainActor (Solid) async -> DisplayMesh?
    @ObservationIgnored private var solids: [Solid] = []
    @ObservationIgnored private var tintTask: Task<Void, Never>?
    @ObservationIgnored private var sliceTask: Task<Void, Never>?
    @ObservationIgnored private var tintGeneration = 0
    @ObservationIgnored private var sliceGeneration = 0

    /// `meshes` gives a shown solid's display mesh once the viewport has it (its vertices are what the field is sampled at).
    init(kernel: any Kernel, distances: FieldDistanceCache?, vertexLimit: Int = CoarseSampling.vertexLimit,
         meshes: @escaping @MainActor (Solid) async -> DisplayMesh?) {
        self.kernel = kernel
        self.distances = distances
        self.vertexLimit = vertexLimit
        self.meshes = meshes
    }

    /// The words for whichever sampling failed (the tint's first).
    var failure: String? { tintFailure ?? sliceFailure }

    /// True while a tint or a slice is being sampled.
    var isSampling: Bool { tintRunning || sliceRunning }

    /// The slice's pose now, or `nil` when it is hidden or there is no part to size it by.
    var pose: SlicePose? {
        guard let field, let bounds else { return nil }
        return SlicePose.pose(for: choice, field: field, bounds: bounds)?.moved(to: offset)
    }

    // MARK: Following

    /// Follows `request`, or stops for `nil`. A request that is the same as the last (the same node and field, the same parts
    /// in the same box) changes nothing; a different one starts a sampling that replaces any under way, and the tint and slice
    /// already shown stay until it publishes. A new node starts its slice over: shown, on the field's own plane or the axis plane
    /// nearest the camera, offset 0.
    func follow(_ request: FieldPreviewRequest?) {
        guard let request else {
            stop()
            return
        }
        let box = Self.bounds(of: request.solids)
        let sameNode = request.node == node
        if sameNode, request.field == field, box == bounds,
           request.solids.map(ObjectIdentifier.init) == solids.map(ObjectIdentifier.init) { return }
        let restartsSlice = !sameNode || (choice == .own && request.field.ownPlane == nil)
        (node, field, solids, bounds) = (request.node, request.field, request.solids, box)
        if restartsSlice {
            choice = SlicePose.startingChoice(for: request.field, toEye: request.toEye)
            offset = 0
            grid = nil
        }
        sampleTints()
        sampleSlice()
        revision += 1
    }

    /// Stops following: cancels any sampling and forgets the field, the tint and the slice. Quiet when there was nothing.
    func stop() {
        guard node != nil || !tints.isEmpty || grid != nil else { return }
        tintTask?.cancel()
        sliceTask?.cancel()
        // A sampling that already finished may still be on its way to `finish…`; a new generation turns it away.
        tintGeneration += 1
        sliceGeneration += 1
        (tintRunning, sliceRunning) = (false, false)
        (node, field, bounds, solids) = (nil, nil, nil, [])
        (tintFailure, sliceFailure) = (nil, nil)
        (tints, grid, choice, offset) = ([:], nil, .hidden, 0)
        revision += 1
    }

    /// Returns once the sampling under way has finished (or been replaced).
    func waitForSampling() async {
        await tintTask?.value
        await sliceTask?.value
    }

    // MARK: The legend's toggles and the handle

    func setUnitRange(_ on: Bool) {
        guard on != usesUnitRange else { return }
        usesUnitRange = on
        revision += 1
    }

    /// Moves the slice to another plane (or hides it): back to offset 0, the old quad gone until the new grid is ready.
    func chooseSlice(_ new: SliceChoice) {
        guard new != choice, field != nil else { return }
        if new == .own, !hasOwnPlane { return }
        choice = new
        offset = 0
        grid = nil
        sampleSlice()
        revision += 1
    }

    /// Moves the slice along its normal (held to the pose's limit); the old grid stays until the new one is ready.
    func moveSlice(to value: Double) {
        guard let pose else { return }
        let moved = pose.moved(to: value).offset
        guard moved != offset else { return }
        offset = moved
        sampleSlice()
        revision += 1
    }

    // MARK: Sampling

    private func sampleTints() {
        tintTask?.cancel()
        tintGeneration += 1
        let generation = tintGeneration
        tintFailure = nil
        guard let field, !solids.isEmpty else {
            tintRunning = false
            tints = [:]
            return
        }
        tintRunning = true
        let (solids, kernel, distances, limit, meshes) = (self.solids, kernel, distances, vertexLimit, meshes)
        tintTask = Task { [weak self] in
            var found: [ObjectIdentifier: SolidTint] = [:]
            do {
                for solid in solids {
                    guard let mesh = await meshes(solid) else { continue }
                    let tint = try await FieldPreviewSampler.tint(of: field, at: mesh.positions, limit: limit, kernel: kernel,
                                                                  cache: distances)
                    found[ObjectIdentifier(solid)] = SolidTint(solid: solid, tint: tint)
                }
            } catch is CancellationError {
                return
            } catch {
                self?.finishTints(generation, found: [:], problem: Self.message(for: error))
                return
            }
            self?.finishTints(generation, found: found, problem: nil)
        }
    }

    private func finishTints(_ generation: Int, found: [ObjectIdentifier: SolidTint], problem: String?) {
        guard generation == tintGeneration else { return }
        tintRunning = false
        tints = found
        tintFailure = problem
        revision += 1
    }

    private func sampleSlice() {
        sliceTask?.cancel()
        sliceGeneration += 1
        let generation = sliceGeneration
        sliceFailure = nil
        guard let field, let pose else {
            sliceRunning = false
            grid = nil
            return
        }
        sliceRunning = true
        let plane = pose.worldPlane
        let size = SlicePose.resolution(for: field)
        let geometry = ViewportSlice(origin: plane.origin, xAxis: plane.xAxis, yAxis: plane.yAxis, halfWidth: pose.halfWidth,
                                     halfHeight: pose.halfHeight, columns: size, rows: size, values: [],
                                     ramp: FieldRamp(low: .zero, mid: .zero, high: .zero, range: 0...1), generation: generation)
        let (kernel, distances) = (kernel, distances)
        sliceTask = Task { [weak self] in
            do {
                let sampled = try await FieldPreviewSampler.gridValues(of: field, in: geometry, kernel: kernel, cache: distances)
                var slice = geometry
                slice.values = sampled.values
                self?.finishSlice(generation, grid: SliceGrid(slice: slice, extent: sampled.extent), problem: nil)
            } catch is CancellationError {
                return
            } catch {
                self?.finishSlice(generation, grid: nil, problem: Self.message(for: error))
            }
        }
    }

    private func finishSlice(_ generation: Int, grid: SliceGrid?, problem: String?) {
        guard generation == sliceGeneration else { return }
        sliceRunning = false
        self.grid = grid
        sliceFailure = problem
        revision += 1
    }

    /// The box round the solids, or `nil` for none.
    static func bounds(of solids: [Solid]) -> BoundingBox? {
        solids.dropFirst().reduce(solids.first?.bounds) { $0?.union($1.bounds) }
    }

    /// A sampling failure in words: the kernel's own, a node error's, or a plain sentence.
    private static func message(for error: any Error) -> String {
        if let kernel = error as? KernelError { return kernel.userMessage }
        if let node = error as? NodeError { return node.message }
        return "The field couldn't be sampled."
    }
}
