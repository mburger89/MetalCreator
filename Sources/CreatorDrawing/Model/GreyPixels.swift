/// An 8-bit grey picture, top row first (DR-5 R12). Immutable and compared by its key and size, so comparing two pictures never
/// compares a megabyte; the key is the hash of the file it came from.
public final class GreyPixels: Hashable, Sendable {
    public let key: String
    public let width: Int
    public let height: Int
    public let bytes: [UInt8]

    /// `nil` unless `bytes.count == width * height` and both sizes are positive.
    public init?(key: String, width: Int, height: Int, bytes: [UInt8]) {
        guard width > 0, height > 0, bytes.count == width * height else { return nil }
        self.key = key
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    public static func == (left: GreyPixels, right: GreyPixels) -> Bool {
        left.key == right.key && left.width == right.width && left.height == right.height
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(key)
        hasher.combine(width)
        hasher.combine(height)
    }
}
