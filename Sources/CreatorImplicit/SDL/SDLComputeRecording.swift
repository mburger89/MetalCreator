#if canImport(MetalUISDLGPU)
import MetalUISDLGPU
import Synchronization

/// Whether a batch's recording on the worker thread failed (a compute pass refused).
final class SDLRecordingFailure: Sendable {
    let failed = Mutex(false)
}

/// One `ComputeBatch` made ready for the device's worker thread: uploads already in transfer buffers, each dispatch's buffers, uniform bytes and
/// group count worked out, the download transfer buffers made. Built and read synchronously; only `record` runs on the worker, in `submitBatch`.
struct SDLComputeRecording: Sendable {
    struct Upload: Sendable {
        let transfer: SDLGPUTransferBuffer
        let buffer: SDLGPUBuffer
        let offset: Int
        let size: Int
    }

    struct Dispatch: Sendable {
        let pipeline: SDLGPUComputePipeline
        let readOnly: [SDLGPUBuffer]
        let readWrite: [SDLGPUBuffer]
        let uniform: [UInt8]
        let groups: Int
    }

    struct Download: Sendable {
        let buffer: SDLGPUBuffer
        let length: Int
        let transfer: SDLGPUTransferBuffer
    }

    let uploads: [Upload]
    let dispatches: [Dispatch]
    let downloads: [Download]
    let failure = SDLRecordingFailure()

    init(_ batch: ComputeBatch, device: SDLGPUDevice) throws {
        guard batch.isWellFormed else {
            throw ImplicitCompileError.engine("a dispatch with buffers its kernel does not declare, or too many groups")
        }
        func sdl(_ buffer: any ComputeBuffer) throws -> SDLGPUBuffer {
            guard let buffer = buffer as? SDLComputeBuffer else { throw ImplicitCompileError.engine("a buffer of another backend") }
            return buffer.buffer
        }
        var uploads: [Upload] = []
        for upload in batch.uploads where !upload.bytes.isEmpty {
            guard let transfer = device.makeTransferBuffer(size: upload.bytes.count, direction: .upload), let memory = transfer.map() else {
                throw ImplicitCompileError.engine("SDL_GPU refused a transfer buffer of \(upload.bytes.count) bytes")
            }
            upload.bytes.withUnsafeBytes { bytes in
                if let base = bytes.baseAddress { memory.copyMemory(from: base, byteCount: bytes.count) }
            }
            transfer.unmap()
            uploads.append(Upload(transfer: transfer, buffer: try sdl(upload.buffer), offset: upload.offset, size: upload.bytes.count))
        }
        var dispatches: [Dispatch] = []
        for dispatch in batch.dispatches where dispatch.threads > 0 {
            guard let pipeline = dispatch.pipeline as? SDLComputePipeline else {
                throw ImplicitCompileError.engine("a pipeline of another backend")
            }
            dispatches.append(Dispatch(
                pipeline: pipeline.pipeline, readOnly: try dispatch.readOnly.map(sdl), readWrite: try dispatch.readWrite.map(sdl),
                uniform: dispatch.parameters.bytes,
                groups: (dispatch.threads + ImplicitKernel.threadsPerGroup - 1) / ImplicitKernel.threadsPerGroup,
            ))
        }
        var downloads: [Download] = []
        for download in batch.downloads {
            guard download.length > 0, let transfer = device.makeTransferBuffer(size: download.length, direction: .download) else {
                throw ImplicitCompileError.engine("SDL_GPU refused a transfer buffer of \(download.length) bytes")
            }
            downloads.append(Download(buffer: try sdl(download.buffer), length: download.length, transfer: transfer))
        }
        self.uploads = uploads
        self.dispatches = dispatches
        self.downloads = downloads
    }

    /// On the worker thread: the uploads, each dispatch in a compute pass of its own, the downloads.
    func record(into commandBuffer: SDLGPUCommandBuffer) {
        for upload in uploads {
            commandBuffer.copy(upload.transfer, to: upload.buffer, destinationOffset: upload.offset, size: upload.size)
        }
        for dispatch in dispatches {
            guard let pass = commandBuffer.beginComputePass(readWrite: dispatch.readWrite) else {
                failure.failed.withLock { $0 = true }
                continue
            }
            pass.bind(dispatch.pipeline)
            if !dispatch.readOnly.isEmpty { pass.bind(readOnly: dispatch.readOnly) }
            pass.push(uniform: dispatch.uniform, at: 0)
            pass.dispatch(x: dispatch.groups, y: 1, z: 1)
            pass.end()
        }
        for download in downloads {
            commandBuffer.copy(download.buffer, range: 0..<download.length, to: download.transfer)
        }
    }

    /// After the fence: each download's bytes.
    func read() -> [[UInt8]] {
        downloads.map { download in
            guard let memory = download.transfer.map() else { return [] }
            defer { download.transfer.unmap() }
            return Array(UnsafeRawBufferPointer(start: memory, count: download.length))
        }
    }

    var hasFailed: Bool { failure.failed.withLock { $0 } }
}
#endif
