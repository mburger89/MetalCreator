extension ViewportModel {
    /// Why the viewport's GPU objects couldn't be made, if they couldn't. The surface is then cleared to dark red.
    public var gpuFailureMessage: String? { gpuFailure }

    /// Main passes the backend has drawn (0 before the first draw, or when the GPU objects could not be made).
    public var drawnFrames: Int { backend?.drawnFrames ?? 0 }

    /// Whether `point` is on a view cube that is both wanted (`showsViewCube`) and drawn (``ViewportBackend/drawsWidgets``). Every cube
    /// hit test goes through here, so a backend that draws no cube leaves the top-left corner to the scene. A model with no backend
    /// yet (before the first draw, and in tests that set `pick` directly) counts the cube as drawn.
    func cubeCatches(_ point: ScreenPoint) -> Bool {
        showsViewCube && (backend?.drawsWidgets ?? true) && cubeLayout.contains(point)
    }

    /// Makes `backend` the code that draws and picks for this model: picks go through it, a hover waits out an ID buffer that is
    /// still on its way, and a landed buffer looks under the pointer again.
    func install(_ backend: any ViewportBackend) {
        self.backend = backend
        pick = { [weak self] point in
            guard let self else { return nil }
            return backend.pick(at: point, in: frame(at: clock.now()))
        }
        isPickPending = { [weak self] in
            guard let self else { return false }
            return backend.isPickPending(for: frame(at: clock.now()))
        }
        pickWhenReady = { [weak self] point in
            guard let self else { return nil }
            return await backend.pickWhenReady(at: point, in: frame(at: clock.now()))
        }
        backend.onPickReady = { [weak self] in self?.refreshHover() }
    }
}
