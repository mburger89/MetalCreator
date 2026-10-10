import Foundation

/// Names for definitions and their sockets (groups spec §4, §5).
public enum GroupNaming {
    /// `base` if no definition has that name, else "base 2", "base 3", …; a `base` that already ends in a number counts on
    /// from it, so a copy of "Rib 2" is "Rib 3", not "Rib 2 2".
    public static func uniqueDefinitionName(_ base: String, among definitions: [GroupID: GroupDefinition]) -> String {
        uniqueName(base, taken: Set(definitions.values.map(\.name)))
    }

    /// `base` if it isn't in `taken`, else "base 2", "base 3", … (see `uniqueDefinitionName`).
    static func uniqueName(_ base: String, taken: Set<String>) -> String {
        guard taken.contains(base) else { return base }
        var stem = base
        var number = 2
        if let space = base.lastIndex(of: " "), space > base.startIndex {
            let digits = base[base.index(after: space)...]
            if !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let own = Int(digits), own < Int.max {
                stem = String(base[..<space])
                number = max(own + 1, 2)
            }
        }
        while taken.contains("\(stem) \(number)") { number += 1 }
        return "\(stem) \(number)"
    }

    /// `base` if no socket in `existing` has it and it isn't a setting's name, else "base2", "base3", …
    public static func uniqueSocketName(_ base: SocketName, among existing: [SocketName]) -> SocketName {
        let taken = Set(existing)
        guard taken.contains(base) || isReserved(base) else { return base }
        var number = 2
        while taken.contains(SocketName("\(base.rawValue)\(number)")) { number += 1 }
        return SocketName("\(base.rawValue)\(number)")
    }

    /// The name of the "+" socket Group Input and Group Output draw to expose a new socket (groups spec §6): no
    /// socket of a definition may have it.
    public static let plusSocket: SocketName = "+"

    /// Socket names that can't be used: a group node keeps its settings (`NodeSetting`) beside its inputs' values,
    /// and the "+" socket is the canvas's.
    public static func isReserved(_ name: SocketName) -> Bool {
        name == plusSocket || NodeSetting.all.contains(name) || name.rawValue.hasPrefix(NodeSetting.projectionPrefix)
    }

    /// Why `sockets` can't be one side of a group, or `nil` if they can.
    static func problem(with sockets: [SocketSpec]) -> String? {
        var seen: Set<SocketName> = []
        for socket in sockets {
            if socket.name.rawValue.trimmingCharacters(in: .whitespaces).isEmpty { return "A socket needs a name." }
            if isReserved(socket.name) { return "“\(socket.name)” is reserved. Choose another name." }
            if !seen.insert(socket.name).inserted { return "Two sockets can't both be named “\(socket.name)”." }
        }
        return nil
    }
}
