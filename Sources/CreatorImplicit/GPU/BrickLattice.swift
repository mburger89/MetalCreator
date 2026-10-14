/// The window of the lattice a set of bricks touches, and the numbering an engine meshes it by (implicit spec Errata D13).
///
/// Every edge of the lattice has one key, `((z * ny + y) * nx + x) * 3 + axis` for the edge from lattice point (x, y, z) along `axis`,
/// counted from the lowest brick of the window: the CPU mesher's global edge key, made relative so that it fits 32 bits for any window
/// of up to about a billion lattice points, however far the part is from the origin. A cube reaches the key of an edge the same way from
/// whichever brick it is in, so a vertex on a brick's face is made once. `UInt32.max` is never a key: engines use it for an empty slot.
public struct BrickLattice: Sendable, Equatable {
    /// The lowest brick coordinates among the bricks.
    public let minBrick: SIMD3<Int32>
    /// How many bricks the window spans on each axis.
    public let extent: SIMD3<Int>

    /// The key an engine uses for "no edge here".
    public static let emptyKey = UInt32.max

    /// The window around `bricks`, or `nil` when there are none.
    public init?(_ bricks: [SIMD3<Int32>]) {
        guard var low = bricks.first else { return nil }
        var high = low
        for brick in bricks {
            low = low.replacing(with: brick, where: brick .< low)
            high = high.replacing(with: brick, where: brick .> high)
        }
        minBrick = low
        extent = SIMD3(Int(high.x) - Int(low.x) + 1, Int(high.y) - Int(low.y) + 1, Int(high.z) - Int(low.z) + 1)
    }

    /// The lattice points on each axis: eight voxels a brick, and the last brick's far layer.
    public var points: SIMD3<Int> { extent &* BrickPlan.brickSize &+ 1 }

    /// Whether every edge key of the window is below `emptyKey`. A window past this is beyond the engines' 32-bit tables, and the CPU
    /// mesher does it.
    public var fitsEdgeKeys: Bool {
        let size = points
        return 3 * Double(size.x) * Double(size.y) * Double(size.z) < Double(Self.emptyKey)
    }

    /// The key of the edge from `point` (counted from the window's lowest lattice point) along `axis` (0 for x, 1 for y, 2 for z).
    /// Only meaningful when `fitsEdgeKeys`.
    public func edgeKey(point: SIMD3<Int>, axis: Int) -> UInt32 {
        let size = points
        return UInt32(((point.z * size.y + point.y) * size.x + point.x) * 3 + axis)
    }

    /// The edge a key names: its lowest lattice point, counted from the window's, and its axis.
    public func edge(of key: UInt32) -> (point: SIMD3<Int>, axis: Int) {
        let size = points
        let index = Int(key) / 3
        return (SIMD3(index % size.x, index / size.x % size.y, index / (size.x * size.y)), Int(key) % 3)
    }

    /// The bricks as x, y, z of each counted from the window's lowest brick, flat: the buffer an engine reads.
    public func relativeBricks(_ bricks: [SIMD3<Int32>]) -> [UInt32] {
        var flat: [UInt32] = []
        flat.reserveCapacity(bricks.count * 3)
        for brick in bricks {
            flat.append(UInt32(bitPattern: brick.x &- minBrick.x))
            flat.append(UInt32(bitPattern: brick.y &- minBrick.y))
            flat.append(UInt32(bitPattern: brick.z &- minBrick.z))
        }
        return flat
    }

    /// The world coordinate of every lattice point of the window along x, then y, then z, as the CPU mesher would compute it in
    /// `Double` and round to `Float`. An engine reads its sample positions from this, so they are the CPU's, bit for bit, and its
    /// vertices need not agree with the CPU's by luck: the same signs, the same crossings.
    public func axisCoordinates(origin: SIMD3<Double>, resolution: Double) -> [Float] {
        let size = points
        let first = SIMD3<Int>(Int(minBrick.x), Int(minBrick.y), Int(minBrick.z)) &* BrickPlan.brickSize
        var coordinates: [Float] = []
        coordinates.reserveCapacity(size.x + size.y + size.z)
        for axis in 0..<3 {
            for index in 0..<size[axis] { coordinates.append(Float(origin[axis] + Double(first[axis] + index) * resolution)) }
        }
        return coordinates
    }
}
