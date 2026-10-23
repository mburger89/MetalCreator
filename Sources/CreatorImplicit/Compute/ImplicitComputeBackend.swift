/// A GPU buffer a backend made.
public protocol ComputeBuffer: AnyObject, Sendable {
    var length: Int { get }
}

/// A compiled kernel a backend made from a `KernelSource`.
public protocol ComputePipeline: AnyObject, Sendable {}

/// What `HLSLImplicitEngine` needs from a GPU API (plan xp-c): buffers, pipelines from kernel sources, and one batch at a time. SDL_GPU on Linux and
/// Windows (`SDLComputeBackend`); in the tests on a Mac, Metal running the MSL of the same HLSL (`MSLComputeBackend`). Nothing here blocks a thread.
public protocol ImplicitComputeBackend: Sendable {
    /// The engine's name for the badge: "Vulkan", "Direct3D 12", "Metal (HLSL)".
    var name: String { get }
    var deviceName: String { get }
    /// The largest storage buffer, in bytes, the engine may make.
    var largestBuffer: Int { get }
    /// A storage buffer of at least `length` bytes; `ImplicitCompileError.unsupported` past `largestBuffer` (that request is the CPU's).
    func makeBuffer(length: Int) throws -> any ComputeBuffer
    /// `source` compiled for this device. Throws `ImplicitCompileError.engine` with the compiler's or the driver's text.
    func makePipeline(_ source: KernelSource) async throws -> any ComputePipeline
    /// The batch in one command buffer: its uploads, each dispatch in a compute pass of its own (SDL_GPU does not synchronize dispatches within one
    /// pass), its downloads; awaits the GPU and returns each download's bytes in order.
    func run(_ batch: ComputeBatch) async throws -> [[UInt8]]
}

/// A backend, or why there is none.
public enum ComputeBackendState: Sendable, CustomStringConvertible {
    case ready(any ImplicitComputeBackend)
    case absent(String)
    case broken(String)

    public var description: String {
        switch self {
        case .ready(let backend): "ready: \(backend.name) on \(backend.deviceName)"
        case .absent(let why): "absent: \(why)"
        case .broken(let why): "broken: \(why)"
        }
    }
}
