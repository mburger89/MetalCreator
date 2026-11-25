import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorNodes
import CreatorViewport
import Observation

/// What the shown control net follows (NS-3, Review Focus 5): the value it was read from, the net read from it, the moves shown with
/// it and the drag in progress. A newer value starts a newer read; only the latest read is ever shown, and the net on screen stays
/// until it lands, so the overlay never mixes two nets.
@MainActor
final class ControlNetFeed {
    let session: ControlNetSession
    /// The solid or curve the net was last asked of; held so its identity is never reused.
    var requested: AnyObject?
    var token = 0
    var grid: ControlNetGrid?
    /// The moves the session was last given, so an unchanged setting is not shown again.
    var sentMoves: [PoleMove] = []
    var dragSerial = 0
    var isDragging = false
    /// Whether the drag in progress has recorded a step, so a cancel takes out only what it made.
    var recordedStep = false
    /// Drag serials count up for the whole run, so no two drags (of any session) share an undo key.
    private static var lastSerial = 0

    static func nextSerial() -> Int {
        lastSerial += 1
        return lastSerial
    }

    init(session: ControlNetSession) {
        self.session = session
    }

    var dragKey: String { "control-points-\(session.node.rawValue.uuidString)-\(dragSerial)" }
}

/// What an Edit Surface or Edit Curve node gets on its input.
enum ControlNetInput: Sendable {
    /// Nothing is wired, or what is wired failed.
    case none
    /// What is wired is still being evaluated.
    case loading
    case several(Int)
    case surface(Solid)
    case curve(Curve)
}

/// The control-point mode in the app (NS-3 rulings R5 to R9): `ControlNetSession` is the viewport's tool while it runs; this reads the
/// net off the main actor, turns the session's moves into undo steps of the node's `poleMoves` and ends the mode when it must.
extension AppModel {
    /// Starts the mode on an Edit Surface or Edit Curve node (its inspector button, a double click). Refused inside a group and for a
    /// node that gets a list; ends Measure and the model dimension tool; does nothing while a sketch is open or a pick runs.
    public func editControlPoints(of id: NodeID) {
        guard sketch == nil else { return }
        if controlNet?.node == id { return }
        guard let node = editor.graph.nodes[id], let kind = Self.controlNetKind(of: node) else { return }
        leaveDrawingForViewport()
        editor.commitPendingEntry()
        editor.closePalette()
        guard !editor.isInsideGroup else {
            let message = "Control points inside a group can't be edited yet. Edit them before grouping, or from the top level."
            alert = .problem(AppProblem("The control points can't be edited here", message))
            return
        }
        if case .several(let count) = controlNetInput(of: node, kind: kind) {
            alert = .problem(AppProblem("The control points can't be edited", Self.listSentence(kind: kind, count: count)))
            return
        }
        pick = nil
        endMeasure()
        endModelDimension()
        endControlPoints()
        let session = ControlNetSession(node: id, kind: kind, events: .init())
        session.events = ControlNetSession.Events(
            moved: { [weak self, weak session] moves, phase in
                guard let self, let session else { return }
                self.controlNetMoved(moves, phase, in: session)
            },
            ended: { [weak self, weak session] in
                guard let self, let session, self.controlNet === session else { return }
                self.endControlPoints()
            }
        )
        controlNet = session
        viewport.tool = session
        followControlNet()
        showMeasureOverlay()
    }

    /// Ends the mode and gives the viewport back; a net shown for the selected node stays, read only.
    public func endControlPoints() {
        guard let session = controlNet else { return }
        session.events = ControlNetSession.Events()
        controlNet = nil
        if viewport.tool === session { viewport.tool = nil }
        if controlNetFeed?.isDragging == true { document.isScrubbing = false }
        document.endCoalescing()
        session.done()
        controlNetFeed = nil
        controlNetRead?.cancel()
        controlNetRead = nil
        controlNetProblem = nil
        followControlNet()
        showMeasureOverlay()
    }

    /// Keeps the Edit node's source in demand while its net is shown (Final preview evaluates only what the Outputs need).
    private func followControlNetDemand(_ source: NodeID?) {
        if let source {
            if document.extraDemand == nil || document.extraDemand == controlNetDemand {
                document.extraDemand = source
                controlNetDemand = source
            }
        } else if let mine = controlNetDemand {
            if document.extraDemand == mine { document.extraDemand = nil }
            controlNetDemand = nil
        }
    }

    static func listSentence(kind: ControlNetSession.Kind, count: Int) -> String {
        "Edit Control Points works on one \(kind == .surface ? "surface" : "curve"); this node gets \(count)."
    }

    static func controlNetKind(of node: Node) -> ControlNetSession.Kind? {
        switch node.typeID {
        case EditSurfaceNode.typeID: .surface
        case EditCurveNode.typeID: .curve
        default: nil
        }
    }

    /// The moves stored on the node, which are what the net shows.
    func storedPoleMoves(of id: NodeID) -> [PoleMove] {
        document.graph.nodes[id]?.inputValues[NodeSetting.poleMoves]?.poleMoves ?? []
    }

    func controlNetInput(of node: Node, kind: ControlNetSession.Kind) -> ControlNetInput {
        let socket: SocketName = kind == .surface ? "surface" : "curve"
        guard let link = document.graph.incomingLink(to: Endpoint(node: node.id, socket: socket)) else { return .none }
        guard let result = document.results[link.from.node] else { return .loading }
        switch result.state {
        case .evaluating: return .loading
        case .idle, .error: return .none
        case .ok, .warning: break
        }
        let items = result.outputs?[link.from.socket]?.items ?? []
        if items.count > 1 { return .several(items.count) }
        switch items.first {
        case .solid(let solid)?: return .surface(solid)
        case .curve(let curve)?: return .curve(curve)
        default: return .none
        }
    }

    // MARK: - Following the document

    /// Called with every scene refresh: ends the mode when its node or level is gone, decides which net is shown (the mode's, or the
    /// selected node's read only), and reads or re-shows it when its input or its moves changed.
    func followControlNet() {
        if let session = controlNet, document.graph.nodes[session.node] == nil || !editor.levelPath.isEmpty {
            endControlPoints()
            return
        }
        let shown = shownControlNetSession()
        if controlNetFeed?.session !== shown {
            controlNetRead?.cancel()
            controlNetRead = nil
            controlNetProblem = nil
            controlNetFeed = shown.map { ControlNetFeed(session: $0) }
            if let feed = controlNetFeed { watchControlNetOverlay(feed) }
        }
        guard let feed = controlNetFeed, let node = document.graph.nodes[feed.session.node] else {
            followControlNetDemand(nil)
            return
        }
        let socket: SocketName = feed.session.kind == .surface ? "surface" : "curve"
        followControlNetDemand(document.graph.incomingLink(to: Endpoint(node: node.id, socket: socket))?.from.node)
        let stored = storedPoleMoves(of: node.id)
        switch controlNetInput(of: node, kind: feed.session.kind) {
        case .loading:
            controlNetProblem = nil
        case .none, .several:
            if case .several(let count) = controlNetInput(of: node, kind: feed.session.kind) {
                controlNetProblem = Self.listSentence(kind: feed.session.kind, count: count)
            } else {
                controlNetProblem = nil
            }
            if feed.requested != nil || feed.grid != nil {
                feed.requested = nil
                feed.grid = nil
                feed.token += 1
                controlNetRead?.cancel()
                controlNetRead = nil
                feed.session.showNet(ControlNetGrid(poles: [], uCount: 0, vCount: 0, normals: []), moves: [])
            }
        case .surface(let solid):
            read(feed, of: solid, input: .surface(solid), stored: stored)
        case .curve(let curve):
            read(feed, of: curve, input: .curve(curve), stored: stored)
        }
    }

    private func read(_ feed: ControlNetFeed, of object: AnyObject, input: ControlNetInput, stored: [PoleMove]) {
        if feed.requested === object {
            if let grid = feed.grid, stored != feed.sentMoves {
                feed.sentMoves = stored
                feed.session.showNet(grid, moves: stored)
            }
            return
        }
        feed.requested = object
        feed.token += 1
        let token = feed.token
        controlNetProblem = nil
        let kernel = self.kernel
        controlNetRead?.cancel()
        controlNetRead = Task { [weak self, weak feed] in
            let result = await Task.detached { () -> Result<ControlNetGrid, any Error> in
                do {
                    switch input {
                    case .surface(let solid):
                        let net = try await kernel.controlNet(of: solid)
                        return .success(ControlNetGrid(poles: net.surface.poles, uCount: net.surface.uCount, vCount: net.surface.vCount,
                                                       normals: net.normals, periodicU: net.surface.isPeriodicU,
                                                       periodicV: net.surface.isPeriodicV))
                    case .curve(let curve):
                        let net = try await kernel.controlNet(of: curve).curve
                        return .success(ControlNetGrid(poles: net.poles, uCount: net.poles.count, vCount: 1, normals: [],
                                                       periodicU: net.isPeriodic))
                    case .none, .loading, .several:
                        return .failure(KernelError.unsupported("control nets"))
                    }
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self, let feed else { return }
            self.controlNetLanded(feed, token: token, result: result)
        }
    }

    func controlNetLanded(_ feed: ControlNetFeed, token: Int, result: Result<ControlNetGrid, any Error>) {
        guard controlNetFeed === feed, token == feed.token else { return }
        controlNetRead = nil
        switch result {
        case .failure(let error):
            // The net on screen belongs to an input that is gone: nothing is shown or draggable until a net can be read.
            controlNetProblem = (error as? KernelError)?.userMessage ?? "\(error)"
            feed.grid = nil
            feed.session.showNet(ControlNetGrid(poles: [], uCount: 0, vCount: 0, normals: []), moves: [])
            showMeasureOverlay()
        case .success(let grid):
            controlNetProblem = nil
            let moves = storedPoleMoves(of: feed.session.node)
            feed.grid = grid
            feed.sentMoves = moves
            feed.session.showNet(grid, moves: moves)
            showMeasureOverlay()
        }
    }

    /// The mode's session, else a read-only one while exactly one Edit Surface or Edit Curve node is selected at the top level.
    private func shownControlNetSession() -> ControlNetSession? {
        if let session = controlNet {
            controlNetPreview = nil
            return session
        }
        guard sketch == nil, pick == nil, !editor.isInsideGroup, editor.selection.count == 1, let id = editor.selection.first,
              let node = document.graph.nodes[id], let kind = Self.controlNetKind(of: node) else {
            controlNetPreview = nil
            return nil
        }
        if let preview = controlNetPreview, preview.node == id, preview.kind == kind { return preview }
        let preview = ControlNetSession(node: id, kind: kind, events: .init())
        controlNetPreview = preview
        return preview
    }

    /// Redraws the viewport's overlay once whenever the shown session changes (its selection, hover, offsets or net).
    private func watchControlNetOverlay(_ feed: ControlNetFeed) {
        withObservationTracking {
            _ = feed.session.overlay
        } onChange: { [weak self, weak feed] in
            MainActor.assumeIsolated {
                guard let self, let feed, self.controlNetFeed === feed, !self.controlNetOverlayPending else { return }
                self.controlNetOverlayPending = true
                Task { @MainActor [weak self, weak feed] in
                    guard let self, let feed else { return }
                    self.controlNetOverlayPending = false
                    guard self.controlNetFeed === feed else { return }
                    self.showMeasureOverlay()
                    self.watchControlNetOverlay(feed)
                }
            }
        }
    }

    // MARK: - Moves

    /// A report from the session: a drag step, a release, a typed value or a cancelled drag, as one undo step each.
    private func controlNetMoved(_ moves: [PoleMove], _ phase: ControlNetSession.DragPhase, in session: ControlNetSession) {
        guard controlNet === session, let feed = controlNetFeed, feed.session === session else { return }
        switch phase {
        case .changed:
            if !feed.isDragging {
                feed.isDragging = true
                feed.recordedStep = false
                feed.dragSerial = ControlNetFeed.nextSerial()
            }
            document.isScrubbing = true
            store(moves, in: feed, key: feed.dragKey, name: UndoName.moveControlPoints)
        case .ended:
            if !feed.isDragging { feed.dragSerial = ControlNetFeed.nextSerial() }
            store(moves, in: feed, key: feed.dragKey, name: UndoName.moveControlPoints)
            feed.isDragging = false
            feed.recordedStep = false
            document.endCoalescing()
            document.isScrubbing = false
        case .typed:
            store(moves, in: feed, key: nil, name: UndoName.changeControlPoint)
        case .cancelled:
            // The drag leaves no step: its run of steps is taken out of the history, and only when there is none the offsets from
            // before it are written back.
            if feed.recordedStep, !document.discardCoalescedStep(key: feed.dragKey) {
                store(moves, in: feed, key: nil, name: UndoName.moveControlPoints)
            }
            feed.isDragging = false
            feed.recordedStep = false
            document.endCoalescing()
            document.isScrubbing = false
            feed.sentMoves = storedPoleMoves(of: session.node)
        }
    }

    /// Merges `moves` into the node's `poleMoves` (a move back to no offset removes it) as one command.
    private func store(_ moves: [PoleMove], in feed: ControlNetFeed, key: String?, name: String) {
        let node = feed.session.node
        var merged: [PoleIndex: Vector3] = [:]
        let stored = storedPoleMoves(of: node)
        for move in stored { merged[move.index] = move.offset }
        for move in moves { merged[move.index] = move.offset == .zero ? nil : move.offset }
        let list = merged.keys.sorted().map { PoleMove(index: $0, offset: merged[$0] ?? .zero) }
        guard list != stored else { return }
        do {
            try document.perform(.setInput(node, NodeSetting.poleMoves, .poleMoves(list)), coalescingKey: key, name: name)
            feed.sentMoves = list
            if key != nil { feed.recordedStep = true }
        } catch {
            alert = .problem(AppProblem("The control points couldn't be moved", error.message))
        }
    }
}
