import CreatorGeometry
import CreatorKernel

extension MeasureSession {
    /// The continuity of one picked edge, asked like the distance of a pair (one pick or two, never both, so they share the task).
    func startContinuity(_ solid: Solid, _ edge: EdgeID) {
        let generation = generation
        isMeasuring = true
        task = Task { [weak self, kernel] in
            do {
                let found = try await kernel.continuity(along: edge, of: solid)
                self?.continuityLanded(found, failed: false, generation: generation)
            } catch is CancellationError {
                return
            } catch KernelError.unsupported {
                self?.continuityLanded(nil, failed: false, generation: generation)
            } catch {
                self?.continuityLanded(nil, failed: true, generation: generation)
            }
        }
    }

    func continuityLanded(_ found: EdgeContinuity?, failed: Bool, generation: Int) {
        guard generation == self.generation else { return }
        continuity = found
        continuityFailed = failed
        isMeasuring = false
        bumpOverlay()
    }

    func startDistance(_ first: MeasurePick, _ second: MeasurePick) {
        let generation = generation
        guard let a = first.element(in: solids), let b = second.element(in: solids) else { return }
        distance = PolylineDistance.shortest(a, b)
        guard distance == nil else { return }
        isMeasuring = true
        task = Task { [weak self, kernel] in
            do {
                let found = try await kernel.shortestDistance(between: a, and: b)
                self?.landed(found, generation: generation)
            } catch is CancellationError {
                return
            } catch {
                self?.refused((error as? KernelError)?.userMessage ?? error.localizedDescription, generation: generation)
            }
        }
    }

    /// A distance for an older pair than the picks now are is dropped.
    func landed(_ found: ShapeDistance, generation: Int) {
        guard generation == self.generation else { return }
        distance = found
        isMeasuring = false
        bumpOverlay()
        dimensionsChanged?()
    }

    func refused(_ message: String, generation: Int) {
        guard generation == self.generation else { return }
        problem = message
        isMeasuring = false
        bumpOverlay()
    }
}
