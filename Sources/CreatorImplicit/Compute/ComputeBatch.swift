public struct ComputeUpload: Sendable {
    public var bytes: [UInt8]
    public var buffer: any ComputeBuffer
    public var offset: Int

    public init(bytes: [UInt8], buffer: any ComputeBuffer, offset: Int = 0) {
        self.bytes = bytes
        self.buffer = buffer
        self.offset = offset
    }
}

/// One kernel over `threads` threads (rounded up to groups of 64; the kernels ignore the extra ones), its storage buffers in declaration order.
public struct ComputeDispatch: Sendable {
    public var kernel: ImplicitKernel
    public var pipeline: any ComputePipeline
    public var parameters: KernelParameters
    public var readOnly: [any ComputeBuffer]
    public var readWrite: [any ComputeBuffer]
    public var threads: Int

    public init(kernel: ImplicitKernel, pipeline: any ComputePipeline, parameters: KernelParameters, readOnly: [any ComputeBuffer],
                readWrite: [any ComputeBuffer], threads: Int) {
        self.kernel = kernel
        self.pipeline = pipeline
        self.parameters = parameters
        self.readOnly = readOnly
        self.readWrite = readWrite
        self.threads = threads
    }
}

public struct ComputeDownload: Sendable {
    public var buffer: any ComputeBuffer
    public var length: Int

    public init(buffer: any ComputeBuffer, length: Int) {
        self.buffer = buffer
        self.length = length
    }
}

/// One command buffer's work.
public struct ComputeBatch: Sendable {
    public var uploads: [ComputeUpload]
    public var dispatches: [ComputeDispatch]
    public var downloads: [ComputeDownload]

    public init(uploads: [ComputeUpload] = [], dispatches: [ComputeDispatch] = [], downloads: [ComputeDownload] = []) {
        self.uploads = uploads
        self.dispatches = dispatches
        self.downloads = downloads
    }

    /// Every dispatch lists the buffers its kernel declares and fits in 65,535 groups (the backends check before they record).
    var isWellFormed: Bool {
        dispatches.allSatisfy { dispatch in
            dispatch.readOnly.count == dispatch.kernel.bindings.readOnly && dispatch.readWrite.count == dispatch.kernel.bindings.readWrite
                && (dispatch.threads + ImplicitKernel.threadsPerGroup - 1) / ImplicitKernel.threadsPerGroup <= ComputeBytes.maximumGroups
        }
    }
}
