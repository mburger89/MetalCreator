import CreatorGraph
import Foundation

/// The text of a node's status badge (spec §6.2): a spinner, the time in ms, ⚠ or ✕. The spinner is MetalUI's
/// `ProgressView` (gap M5-j), drawn by `StatusBadgeView` while `isBusy`, so it has no text.
public enum StatusBadge {
    public static func text(for state: NodeState?) -> String {
        switch state {
        case .evaluating?: ""
        case .ok(let duration)?: milliseconds(duration)
        case .warning?: "⚠"
        case .error?: "✕"
        case .idle?, nil: ""
        }
    }

    /// Whether the badge shows the spinner: the node is being evaluated.
    public static func isBusy(_ state: NodeState?) -> Bool {
        state == .evaluating
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
