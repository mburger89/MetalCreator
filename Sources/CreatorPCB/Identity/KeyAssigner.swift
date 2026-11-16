import Foundation

/// Gives every drilled hole its identity string and refuses two different strings that hash to one key.
public enum KeyAssigner {
    public static func assign(_ board: inout KiCadBoard, isCancelled: () -> Bool = { false }) throws {
        try assign(&board, hash: KiCadKey.fnv1a64, isCancelled: isCancelled)
    }

    /// Cancellation is asked every this many items.
    static let cancelEvery = 4_096

    static func assign(_ board: inout KiCadBoard, hash: (String) -> UInt64, isCancelled: () -> Bool = { false }) throws {
        let tokens = footprintTokens(board.footprints)
        var taken = Set<String>()
        var strings: [String] = []
        /// The first use of a string keeps it; a repeat gets "#2", "#3" (in file order: edges, pads, vias).
        /// The next suffix to try is kept per base string, so a thousand repeats cost a thousand probes, not a million.
        var nextSuffix: [String: Int] = [:]
        func unique(_ text: String) -> String {
            var result = text
            if taken.contains(result) {
                var count = nextSuffix[text] ?? 1
                repeat {
                    count += 1
                    result = "\(text)#\(count)"
                } while taken.contains(result)
                nextSuffix[text] = count
            }
            taken.insert(result)
            strings.append(result)
            return result
        }
        var steps = 0
        func tick() throws {
            steps += 1
            if steps % cancelEvery == 0, isCancelled() { throw CancellationError() }
        }
        for index in board.edgeItems.indices {
            try tick()
            board.edgeItems[index].identity = unique(board.edgeItems[index].identity)
        }
        for index in board.footprints.indices {
            var seen: [String: Int] = [:]
            for hole in board.footprints[index].holes.indices {
                try tick()
                let number = board.footprints[index].holes[hole].padNumber
                let base = "pad:\(tokens[index]):\(number)"
                board.footprints[index].holes[hole].identity = unique(numbered(base, &seen))
            }
        }
        var seenVias: [String: Int] = [:]
        for index in board.vias.indices {
            try tick()
            let centre = board.vias[index].center
            let name = board.vias[index].uuid.flatMap { $0.isEmpty ? nil : $0 }
                ?? "\(nanometres(centre.x)),\(nanometres(centre.y))"
            board.vias[index].identity = unique(numbered("via:\(name)", &seenVias))
        }
        try refuseSharedKeys(strings, hash: hash, tick: tick)
    }

    private static func refuseSharedKeys(_ strings: [String], hash: (String) -> UInt64, tick: () throws -> Void) throws {
        var owner: [UInt64: String] = [:]
        for text in strings {
            try tick()
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
