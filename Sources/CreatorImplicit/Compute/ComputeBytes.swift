/// The engine's synchronous byte work: packing for an upload, reading back, cutting a count into ranges. Synchronous on purpose (the Windows Swift 6.4
/// compiler asserts on an `async` function that holds a loop's locals across an `await`).
enum ComputeBytes {
    /// The most thread groups one dispatch has (Vulkan's guaranteed `maxComputeWorkGroupCount`; gap XP-G24).
    static let maximumGroups = 65_535

    static func bytes<Value>(of values: [Value]) -> [UInt8] {
        values.withUnsafeBytes { Array($0) }
    }

    /// Points as three floats each (`SIMD3<Float>` is 16 bytes; Metal's kernel reads `packed_float3`).
    static func packed(_ points: ArraySlice<SIMD3<Float>>) -> [UInt8] {
        var flat: [Float] = []
        flat.reserveCapacity(points.count * 3)
        for point in points {
            flat.append(point.x)
            flat.append(point.y)
            flat.append(point.z)
        }
        return bytes(of: flat)
    }

    static func values<Value: BitwiseCopyable>(_ bytes: [UInt8], as type: Value.Type) -> [Value] {
        let count = bytes.count / MemoryLayout<Value>.stride
        return [Value](unsafeUninitializedCapacity: count) { buffer, initialized in
            bytes.withUnsafeBytes { raw in
                let used = UnsafeRawBufferPointer(rebasing: raw[0..<(count * MemoryLayout<Value>.stride)])
                UnsafeMutableRawBufferPointer(buffer).copyMemory(from: used)
            }
            initialized = count
        }
    }

    static func ranges(count: Int, size: Int) -> [Range<Int>] {
        stride(from: 0, to: count, by: max(1, size)).map { $0..<min($0 + max(1, size), count) }
    }
}
