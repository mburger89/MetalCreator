import CreatorGeometry
import CreatorKernel

public enum ViewExtents {
    /// The box's size along the frame's right, up and direction, from its eight corners.
    public static func of(_ bounds: BoundingBox, frame: ProjectionFrame) -> (width: Double, height: Double, depth: Double) {
        let right = frame.right
        var low = [Double.infinity, .infinity, .infinity]
        var high = [-Double.infinity, -.infinity, -.infinity]
        for x in [bounds.min.x, bounds.max.x] {
            for y in [bounds.min.y, bounds.max.y] {
                for z in [bounds.min.z, bounds.max.z] {
                    let p = Vector3(x, y, z)
                    let values = [p.dot(right), p.dot(frame.up), p.dot(frame.direction)]
                    for i in 0..<3 {
                        low[i] = Swift.min(low[i], values[i])
                        high[i] = Swift.max(high[i], values[i])
                    }
                }
            }
        }
        return (high[0] - low[0], high[1] - low[1], high[2] - low[2])
    }
}
