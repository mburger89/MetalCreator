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

    /// Remap's maths (fields spec §3.2): the linear map of the from range onto the to range, held to the to range when
    /// `clamped`. An empty from range gives `toLow`.
    static func remap(_ value: Double, fromLow: Double, fromHigh: Double, toLow: Double, toHigh: Double, clamped: Bool) -> Double {
        guard fromHigh != fromLow else { return toLow }
        let mapped = toLow + (value - fromLow) / (fromHigh - fromLow) * (toHigh - toLow)
        guard clamped else { return mapped }
        return min(max(mapped, min(toLow, toHigh)), max(toLow, toHigh))
    }

    /// Smooth Blend's maths (fields spec §3.2): the polynomial smooth minimum over `width`; width 0 is the plain minimum.
    static func smoothMinimum(_ a: Double, _ b: Double, width: Double) -> Double {
        guard width > 0 else { return min(a, b) }
        let blend = max(width - abs(a - b), 0) / width
        return min(a, b) - blend * blend * width / 4
    }
}
