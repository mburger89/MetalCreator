import CreatorKernel
import CreatorViewport

/// Stands in for the graph while a handle is dragged: each new value rebuilds the part and re-shows it, as the
/// app will by editing the node's input and re-evaluating (spec §6.5, §7.3). One build runs at a time and the
/// newest value wins.
@MainActor
final class HarnessRebuilder {
    private let kernel: any Kernel
    private let selection: HarnessSelection
    private let ghost: Bool
    private let selectTop: Bool
    private(set) var thickness = 6.0
    private(set) var filletRadius = 3.0
    private var build: Task<Void, Never>?
    private var isStale = false

    init(kernel: any Kernel, selection: HarnessSelection, ghost: Bool, selectTop: Bool) {
        self.kernel = kernel
        self.selection = selection
        self.ghost = ghost
        self.selectTop = selectTop
    }

    /// Applies a handle's new value and rebuilds. Unknown handle IDs only rebuild.
    func handleChanged(_ id: String, to value: Double, on model: ViewportModel) {
        switch id {
        case "plate.distance": thickness = value
        case "fillet.radius": filletRadius = value
        default: break
        }
        rebuild(on: model)
    }

    /// Builds the latest values. While a build runs, newer values wait and only the newest is built next:
    /// cancelling a task doesn't interrupt an OCCT call, so starting a build per drag event would queue them all
    /// behind the kernel lock and the part would fall further and further behind the pointer.
    func rebuild(on model: ViewportModel) {
        guard build == nil else {
            isStale = true
            return
        }
        build = Task { [weak self, weak model] in
            while let self, let model {
                self.isStale = false
                let (thickness, radius) = (self.thickness, self.filletRadius)
                let started = ContinuousClock.now
                do {
                    let scene = try await HarnessScene.build(self.kernel, thickness: thickness, filletRadius: radius,
                                                             ghost: self.ghost, selectTop: self.selectTop)
                    let elapsed = (ContinuousClock.now - started).formatted(.units(allowed: [.milliseconds]))
                    print("rebuilt in \(elapsed)")
                    self.selection.show(scene.items, on: model)
                    model.showHandles(scene.handles)
                } catch {
                    print("ViewportHarness: \(error)")
                }
                guard self.isStale else { break }
            }
            self?.build = nil
        }
    }
}
