#if canImport(Compression)
import Compression

/// Raw DEFLATE (RFC 1951), the compression a zip entry of method 8 holds, by Apple's Compression framework: `COMPRESSION_ZLIB` is
/// deflate without the zlib header. The only file that names the framework; elsewhere zip entries are stored (`ZipWriter.defaultMethod`).
final class RawDeflater {
    private static let bufferSize = 1 << 16
    private var stream: compression_stream
    private let output: UnsafeMutablePointer<UInt8>
    private let placeholder: UnsafeMutablePointer<UInt8>

    init() throws {
        output = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.bufferSize)
        placeholder = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        stream = compression_stream(dst_ptr: output, dst_size: Self.bufferSize, src_ptr: UnsafePointer(placeholder), src_size: 0,
                                    state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            output.deallocate()
            placeholder.deallocate()
            throw ZipError.compressionFailed
        }
    }

    deinit {
        compression_stream_destroy(&stream)
        output.deallocate()
        placeholder.deallocate()
    }

    /// Compresses `input`, handing every piece of output to `emit`. With `finish`, the stream is ended and everything left is emitted.
    func process(_ input: UnsafeRawBufferPointer, finish: Bool, emit: (UnsafeBufferPointer<UInt8>) throws -> Void) throws {
        stream.src_ptr = input.baseAddress.map { UnsafePointer($0.assumingMemoryBound(to: UInt8.self)) } ?? UnsafePointer(placeholder)
        stream.src_size = input.count
        let flags: Int32 = finish ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0
        while true {
            stream.dst_ptr = output
            stream.dst_size = Self.bufferSize
            let status = compression_stream_process(&stream, flags)
            guard status != COMPRESSION_STATUS_ERROR else { throw ZipError.compressionFailed }
            let produced = Self.bufferSize - stream.dst_size
            if produced > 0 { try emit(UnsafeBufferPointer(start: output, count: produced)) }
            if status == COMPRESSION_STATUS_END || (!finish && stream.src_size == 0 && stream.dst_size > 0) { break }
        }
    }
}
#endif
