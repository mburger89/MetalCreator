import CreatorGraph
import Foundation

/// The text of a node's status badge (spec §6.2): a spinner, the time in ms, ⚠ or ✕.
public enum StatusBadge {
    public static func text(for state: NodeState?) -> String {
        switch state {
        case .evaluating?: "◌"
        case .ok(let duration)?: milliseconds(duration)
        case .warning?: "⚠"
        case .error?: "✕"
        case .idle?, nil: ""
        }
    }

    /// The message a badge's tooltip shows, if any.
    public static func message(for state: NodeState?) -> String? {
        switch state {
        case .warning(let message)?, .error(let message)?: message
        case .idle(let reason?)?: reason
        default: nil
        }
    }

    static func milliseconds(_ duration: Duration) -> String {
        let ms = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        if ms < 1 { return "<1 ms" }
        return "\(ms.formatted(.number.precision(.fractionLength(0)).grouping(.never).locale(ValueText.locale))) ms"
    }
}
