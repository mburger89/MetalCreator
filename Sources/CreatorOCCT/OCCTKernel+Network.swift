import COCCT
import CreatorGeometry
import CreatorKernel
import Foundation

/// A flag a task's cancellation sets so a long shim call stops between its steps.
final class OCCTCancelFlag: Sendable {
    private let address: UInt

    var raw: OpaquePointer { OpaquePointer(bitPattern: address)! }

    init() { address = UInt(bitPattern: occt_cancel_new()) }

    func cancel() { occt_cancel_set(raw) }

    deinit { occt_cancel_free(raw) }

    /// What the shim says when it stopped on the flag.
    static let message = "The operation was cancelled."
}

extension OCCTShape {
    /// The Gordon surface through `u` and `v` curves. Call under `OCCTKernel.serialized`.
    static func networkSurface(u: [OCCTShape], v: [OCCTShape], tolerance: Double, cancel: OCCTCancelFlag)
        throws(OCCTError) -> SheetBuild {
        let uPointers: [OpaquePointer?] = u.map(\.raw)
        let vPointers: [OpaquePointer?] = v.map(\.raw)
        return try buildingSheet { history, roles, status in
            uPointers.withUnsafeBufferPointer { uBuffer in
                vPointers.withUnsafeBufferPointer { vBuffer in
                    occt_network_surface(uBuffer.baseAddress, Int32(uBuffer.count), vBuffer.baseAddress, Int32(vBuffer.count),
                                         tolerance, cancel.raw, history, roles, status)
                }
            }
        }
    }
}

extension OCCTKernel {
    public func networkSurface(u: [Curve], v: [Curve], tolerance: Double, tag: NodeTag) async throws -> Solid {
        try Task.checkCancellation()
        guard u.count >= 2, v.count >= 2 else {
            throw KernelError.invalidInput("A network needs at least two curves in each direction.")
        }
        guard tolerance.isFinite, tolerance > 0 else {
            throw KernelError.invalidInput("The tolerance must be greater than 0 mm.")
        }
        let uWires = try u.map { try curveShape(of: $0) }
        let vWires = try v.map { try curveShape(of: $0) }
        let flag = OCCTCancelFlag()
        let result: Solid
        do {
            result = try await withTaskCancellationHandler {
                try buildSheet("network surface", tag: tag) {
                    try OCCTShape.networkSurface(u: uWires, v: vWires, tolerance: tolerance, cancel: flag)
                }
            } onCancel: {
                flag.cancel()
            }
        } catch KernelError.invalidInput(let message) {
            if message == OCCTCancelFlag.message { throw CancellationError() }
            throw KernelError.invalidInput(Self.writingNumbers(in: message))
        }
        try Task.checkCancellation()
        return result
    }

    /// The shim marks each number in a refusal with \u{1}…\u{2}; this writes them in the message locale.
    static func writingNumbers(in message: String) -> String {
        var out = ""
        var rest = Substring(message)
        while let open = rest.firstIndex(of: "\u{1}") {
            out += rest[rest.startIndex..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "\u{2}") else {
                rest = rest[afterOpen...]
                continue
            }
            let text = rest[afterOpen..<close]
            out += Double(text)?.gapText() ?? String(text)
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }
}
