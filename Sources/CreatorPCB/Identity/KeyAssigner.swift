import Foundation

/// Gives every drilled hole its identity string and refuses two different strings that hash to one key.
public enum KeyAssigner {
    public static func assign(_ board: inout KiCadBoard) throws {
        try assign(&board, hash: KiCadKey.fnv1a64)
    }

    static func assign(_ board: inout KiCadBoard, hash: (String) -> UInt64) throws {
        let tokens = footprintTokens(board.footprints)
        var strings: [String] = board.edgeItems.map(\.identity)
        for index in board.footprints.indices {
            var seen: [String: Int] = [:]
            for hole in board.footprints[index].holes.indices {
                let number = board.footprints[index].holes[hole].padNumber
                let base = "pad:\(tokens[index]):\(number)"
                let identity = numbered(base, &seen)
                board.footprints[index].holes[hole].identity = identity
                strings.append(identity)
            }
        }
        var seenVias: [String: Int] = [:]
        for index in board.vias.indices {
            let centre = board.vias[index].center
            let name = board.vias[index].uuid.flatMap { $0.isEmpty ? nil : $0 } ?? "\(nanometres(centre.x)),\(nanometres(centre.y))"
            let identity = numbered("via:\(name)", &seenVias)
            board.vias[index].identity = identity
            strings.append(identity)
        }
        var owner: [UInt64: String] = [:]
        for text in strings {
            let key = hash(text) & 0x0FFF_FFFF_FFFF_FFFF
            if let other = owner[key], other != text {
                throw KiCadProblem("Two items in this board share an internal name (\(other) and \(text)). "
                    + "Rename one in KiCad and try again.")
            }
            owner[key] = text
        }
    }

    /// A footprint's reference when non-empty and unique, else its uuid, else its place in the file.
    private static func footprintTokens(_ footprints: [Footprint]) -> [String] {
        var references: [String: Int] = [:]
        var uuids: [String: Int] = [:]
        for footprint in footprints {
            references[footprint.reference, default: 0] += 1
            if let uuid = footprint.uuid { uuids[uuid, default: 0] += 1 }
        }
        return footprints.enumerated().map { index, footprint in
            if !footprint.reference.isEmpty, references[footprint.reference] == 1 { return footprint.reference }
            if let uuid = footprint.uuid, !uuid.isEmpty, uuids[uuid] == 1 { return "uuid:\(uuid)" }
            return "fp#\(index)"
        }
    }

    /// The first use of `base` keeps it; later ones add ":2", ":3".
    private static func numbered(_ base: String, _ seen: inout [String: Int]) -> String {
        let count = (seen[base] ?? 0) + 1
        seen[base] = count
        return count == 1 ? base : "\(base):\(count)"
    }

    /// `value` to 1 nm as decimal text, without a locale.
    static func nanometres(_ value: Double) -> String {
        let total = Int64((value * 1_000_000).rounded())
        let magnitude = total.magnitude
        let fraction = String(magnitude % 1_000_000)
        let padded = String(repeating: "0", count: 6 - fraction.count) + fraction
        return "\(total < 0 ? "-" : "")\(magnitude / 1_000_000).\(padded)"
    }
}
