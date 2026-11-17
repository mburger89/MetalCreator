/// Why a stored model's zstd frame was refused. Every message is a sentence for the person.
public struct ZstdProblem: Error, Equatable, Sendable {
    public let message: String

    public init(_ message: String) { self.message = message }

    /// Any malformed frame.
    public static let damaged = ZstdProblem("The stored model is damaged.")
    public static let dictionary = ZstdProblem("The stored model uses a zstd dictionary, which isn't supported.")
    public static let window = ZstdProblem("The stored model needs more memory to unpack than this app allows.")

    public static func larger(than limit: Int) -> ZstdProblem {
        let size = limit >= 1 << 20 ? "\(limit >> 20) MB" : "\(limit) bytes"
        return ZstdProblem("The stored model is larger than \(size).")
    }
}
