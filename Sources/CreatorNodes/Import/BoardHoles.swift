import CreatorGeometry
import CreatorKernel
import CreatorPCB
import Foundation

/// The drilled holes of an imported board: their tools, their placements and which of them are mounting holes.
enum BoardHoles {
    /// One tool per distinct drill: a round hole or a slot.
    struct Size: Hashable {
        var diameter: Double
        var slotLength: Double?
    }

    /// A hole in the board frame (the origin already subtracted), with the item its faces carry.
    struct Placed {
        var hole: DrilledHole
        var center: Vector2
        var item: Int
        var size: Size { Size(diameter: hole.diameter, slotLength: hole.slotLength) }

        /// The hole tool's place: at the centre, its x axis along the slot.
        var plane: Plane {
            let turn = hole.angle * .pi / 180
            return Plane(origin: Vector3(center.x, center.y, 0), normal: Vector3(0, 0, 1),
                         xAxis: Vector3(cos(turn), sin(turn), 0))
        }
    }

    /// The tool for `size`: a prism from 1 mm under the board to 1 mm over it, facing +z at the origin.
    static func profile(for size: Size) -> Profile2D {
        let base = Plane.xy.offset(by: -1)
        if let length = size.slotLength { return .slot(length: length, width: size.diameter, plane: base) }
        return .circle(radius: size.diameter / 2, center: Vector2(0, 0), plane: base)
    }

    /// Every pad hole of the board, then the vias when asked, moved by `-origin`, in file order.
    static func placed(_ board: KiCadBoard, origin: Vector2, vias: Bool) -> [Placed] {
        var holes = board.footprints.flatMap(\.holes)
        if vias { holes += board.vias }
        return holes.map { Placed(hole: $0, center: $0.center - origin, item: KiCadKey.item(for: $0.identity)) }
    }

    /// One mounting hole: where it is (in the board frame) and its diameter.
    struct Mounting {
        var center: Vector2
        var diameter: Double
    }

    /// The board's mounting holes (KiCad import spec, Outputs): each hole of a footprint whose library name starts with
    /// `MountingHole`, or the one hole of a footprint that has exactly one and it is non-plated, round and at least 2 mm.
    /// Ordered by the footprint's reference (digits compared as numbers), then the pad's identity.
    static func mounting(_ board: KiCadBoard, origin: Vector2) -> [Mounting] {
        var found: [(reference: String, identity: String, mounting: Mounting)] = []
        for footprint in board.footprints {
            let name = footprint.libraryID.split(separator: ":", maxSplits: 1).last.map(String.init) ?? footprint.libraryID
            let isMountingName = name.hasPrefix("MountingHole")
            let isLoneBigHole = footprint.holes.count == 1 && footprint.holes.contains {
                !$0.isPlated && $0.slotLength == nil && $0.diameter >= 2
            }
            guard isMountingName || isLoneBigHole else { continue }
            for hole in footprint.holes {
                found.append((footprint.reference, hole.identity, Mounting(center: hole.center - origin, diameter: hole.diameter)))
            }
        }
        found.sort { lhs, rhs in
            if lhs.reference != rhs.reference { return naturallyOrdered(lhs.reference, before: rhs.reference) }
            return lhs.identity < rhs.identity
        }
        return found.map(\.mounting)
    }

    /// Natural order: the text split into runs of digits and of anything else, digit runs compared as numbers ("H2" < "H10").
    static func naturallyOrdered(_ a: String, before b: String) -> Bool {
        let (x, y) = (runs(a), runs(b))
        for (left, right) in zip(x, y) where left != right {
            if let m = left.number, let n = right.number, m != n { return m < n }
            if left.number != nil, right.number == nil { return true }
            if left.number == nil, right.number != nil { return false }
            return left.text < right.text
        }
        return x.count < y.count
    }

    private struct Run: Equatable {
        var text: String
        var number: Int?
    }

    private static func runs(_ text: String) -> [Run] {
        var result: [Run] = []
        var current = ""
        var isDigits = false
        func flush() {
            guard !current.isEmpty else { return }
            result.append(Run(text: current, number: isDigits ? Int(current.prefix(18)) : nil))
            current = ""
        }
        for character in text {
            let digit = character.isASCII && character.isNumber
            if !current.isEmpty, digit != isDigits { flush() }
            isDigits = digit
            current.append(character)
        }
        flush()
        return result
    }
}
