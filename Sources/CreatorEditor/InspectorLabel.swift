import CreatorGraph

/// Readable labels from socket names: "cornerRadius" → "Corner radius".
public enum InspectorLabel {
    public static func text(for socket: SocketName) -> String {
        var words: [String] = []
        var current = ""
        for character in socket.rawValue {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        let sentence = words.map { $0.lowercased() }.joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }
}
