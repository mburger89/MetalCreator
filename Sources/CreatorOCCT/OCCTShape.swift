import COCCT
import Foundation

/// Owns one OCCT shape. A built shape's geometry is not mutated, but OCCT operations are
/// not read-only: meshing (BRepMesh) writes triangulation into the shared TShape. So all
/// OCCT access runs under `OCCTKernel.serialized`, a process-wide lock (shapes share geometry
/// across solids and kernels, so per-actor isolation is not enough). Freeing from any thread
/// in `deinit` is safe (OCCT reference counts are atomic); the pointer is freed exactly once.
final class OCCTShape: Sendable {
    // `OpaquePointer` is not Sendable. The pointer is a `let` and is only freed in `deinit`
    // (atomic refcounts). Soundness of concurrent use relies on every OCCT call that reads or
    // mutates the shape (e.g. meshing) running under the process-wide `OCCTKernel.serialized`
    // lock, as described above.
    nonisolated(unsafe) let raw: OpaquePointer

    init(raw: OpaquePointer) {
        self.raw = raw
    }

    deinit {
        occt_shape_free(raw)
    }

    static func box(_ dx: Double, _ dy: Double, _ dz: Double) throws(OCCTError) -> OCCTShape {
        try make { status in occt_make_box(dx, dy, dz, status) }
    }

    var volume: Double { occt_volume(raw) }
    var faceCount: Int { Int(occt_face_count(raw)) }
    var edgeCount: Int { Int(occt_edge_count(raw)) }

    /// Length of the edge at 1-based `index`, or -1 when out of range.
    func edgeLength(at index: Int) -> Double {
        occt_edge_length(raw, Int32(index))
    }

    func filleting(edge index: Int, radius: Double) throws(OCCTError) -> OCCTShape {
        try Self.make { status in occt_fillet_edge(raw, Int32(index), radius, status) }
    }

    func writeSTEP(to url: URL) throws(OCCTError) {
        try Self.check { status in url.withUnsafeFileSystemRepresentation { occt_write_step(raw, $0, status) } }
    }

    func writeSTL(to url: URL, deflection: Double) throws(OCCTError) {
        try Self.check { status in
            url.withUnsafeFileSystemRepresentation { occt_write_stl(raw, $0, deflection, status) }
        }
    }

    /// Calls a shim function returning 1/0 and turns failure into `OCCTError`.
    static func check(_ body: (UnsafeMutablePointer<occt_status>) -> Int32) throws(OCCTError) {
        var status = occt_status()
        let result = body(&status)
        guard status.ok != 0, result == 1 else {
            throw OCCTError(message: status.messageText)
        }
    }

    /// Calls a shim constructor and turns a null result or error status into `OCCTError`.
    static func make(_ body: (UnsafeMutablePointer<occt_status>) -> OpaquePointer?) throws(OCCTError) -> OCCTShape {
        var status = occt_status()
        let result = body(&status)
        guard status.ok != 0, let result else {
            throw OCCTError(message: status.messageText)
        }
        return OCCTShape(raw: result)
    }
}

extension occt_status {
    /// The NUL-terminated `message` buffer as a Swift string.
    var messageText: String {
        withUnsafeBytes(of: message) { bytes in
            // `bytes` is a raw C buffer, not `Data`; the lossy non-failable decode is intended here.
            // swiftlint:disable:next optional_data_string_conversion
            let text = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            return text.isEmpty ? "unknown OCCT error" : text
        }
    }
}
