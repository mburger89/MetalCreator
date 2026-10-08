import Metal

enum GPUBuffers {
    /// A shared buffer holding `values`, or `nil` for an empty array (Metal refuses zero-length buffers).
    static func make<T>(_ device: any MTLDevice, _ values: [T]) -> (any MTLBuffer)? {
        guard !values.isEmpty else { return nil }
        return values.withUnsafeBytes { bytes in
            bytes.baseAddress.flatMap { device.makeBuffer(bytes: $0, length: bytes.count, options: .storageModeShared) }
        }
    }
}
