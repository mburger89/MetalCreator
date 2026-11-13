import CreatorGraph

/// Readable labels from socket names: "cornerRadius" → "Corner radius".
public enum InspectorLabel {
    public static func text(for socket: SocketName) -> String { SocketLabel.text(for: socket) }
}
