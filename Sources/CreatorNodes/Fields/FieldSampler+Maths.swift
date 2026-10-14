import CreatorGeometry

extension FieldSampler {
    /// `transform` of each point, in chunks, checking for cancellation between them.
    static func map(_ points: [Vector3], _ transform: (Vector3) -> Double) throws -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(points.count)
        var start = 0
        while start < points.count {
            try Task.checkCancellation()
            let end = min(start + chunkSize, points.count)
            for index in start..<end { result.append(transform(points[index])) }
            start = end
        }
        return result
    }

    /// `transform` of each number, in chunks.
    static func map(_ values: [Double], _ transform: (Double) -> Double) throws -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(values.count)
        var start = 0
        while start < values.count {
            try Task.checkCancellation()
            let end = min(start + chunkSize, values.count)
            for index in start..<end { result.append(transform(values[index])) }
            start = end
        }
        return result
    }

    /// `transform` of each pair, in chunks. Both arrays are the length of the batch.
    static func combine(_ a: [Double], _ b: [Double], _ transform: (Double, Double) -> Double) throws -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(a.count)
        var start = 0
        while start < a.count {
            try Task.checkCancellation()
            let end = min(start + chunkSize, a.count)
            for index in start..<end { result.append(transform(a[index], b[index])) }
            start = end
        }
        return result
    }

    /// Remap's maths (fields spec §3.2); `FieldMath.remap`.
    static func remap(_ value: Double, fromLow: Double, fromHigh: Double, toLow: Double, toHigh: Double, clamped: Bool) -> Double {
        FieldMath.remap(value, fromLow: fromLow, fromHigh: fromHigh, toLow: toLow, toHigh: toHigh, clamped: clamped)
    }

    /// The smaller of two numbers, `.nan` when either is (`FieldMath.minimum`).
    static func minimum(_ a: Double, _ b: Double) -> Double { FieldMath.minimum(a, b) }

    /// The larger of two numbers, `.nan` when either is (`FieldMath.maximum`).
    static func maximum(_ a: Double, _ b: Double) -> Double { FieldMath.maximum(a, b) }

    /// Clamp's maths (`FieldMath.clamp`).
    static func clamp(_ value: Double, low: Double, high: Double) -> Double { FieldMath.clamp(value, low: low, high: high) }

    /// Smooth Blend's maths (`FieldMath.smoothMinimum`).
    static func smoothMinimum(_ a: Double, _ b: Double, width: Double) -> Double {
        FieldMath.smoothMinimum(a, b, width: width)
    }
}
