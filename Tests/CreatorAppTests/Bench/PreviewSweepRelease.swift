// Test fixture file: weak references that show an app's meshes are freed when it is released (preview sweep, Errata D15).
import CreatorKernel
import Foundation
#if canImport(Darwin)
import Darwin
#endif
#if canImport(Metal)
import Metal
#endif
@testable import CreatorApp
@testable import CreatorViewport

/// Weak references to what one rung's app built, to check the app lets go of its meshes when it is released.
@MainActor
struct PreviewSweepRelease {
    weak var app: AppModel?
    weak var viewport: ViewportModel?
    weak var renderer: AnyObject?
    /// The mesh payloads (`DisplayMeshStorage`) of the viewport's solids.
    var storages: [WeakStorage]

    struct WeakStorage {
        weak var storage: AnyObject?
    }

    init(app: AppModel, renderer: AnyObject?, solids: [Solid]) {
        self.app = app
        viewport = app.viewport
        self.renderer = renderer
        storages = solids.map { WeakStorage(storage: $0.storage as AnyObject) }
    }

    /// How many of the watched objects are still alive.
    var survivors: [String] {
        var alive: [String] = []
        if app != nil { alive.append("AppModel") }
        if viewport != nil { alive.append("ViewportModel") }
        if renderer != nil { alive.append("renderer") }
        let meshes = storages.filter { $0.storage != nil }.count
        if meshes > 0 { alive.append("\(meshes) mesh storage") }
        return alive
    }

    func describe() -> String {
        survivors.isEmpty ? "AppModel, renderer and mesh storage freed" : "STILL ALIVE: \(survivors.joined(separator: ", "))"
    }

    /// The bytes the default Metal device has allocated (buffers, textures, heaps) at this moment.
    static var metalAllocated: Int {
        #if canImport(Metal)
        MTLCreateSystemDefaultDevice()?.currentAllocatedSize ?? 0
        #else
        0
        #endif
    }

    /// Asks malloc to give freed pages back to the system, as a process under memory pressure does.
    static func returnFreedMemory() {
        #if canImport(Darwin)
        _ = malloc_zone_pressure_relief(nil, 0)
        #endif
    }

    /// Bytes malloc has handed out and not had back, over every zone.
    static var heapInUse: Int {
        #if canImport(Darwin)
        var statistics = malloc_statistics_t()
        malloc_zone_statistics(nil, &statistics)
        return Int(statistics.size_in_use)
        #else
        0
        #endif
    }
}
