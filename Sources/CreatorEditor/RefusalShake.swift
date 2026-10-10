import MetalUI

/// The refused edit's shake (spec §6.2): the refused node jumps 6 points right, 6 left and back to rest in a fifth of a
/// second. The keyframes are MetalUI's (gap M5-i, `keyframeAnimator`); `NodeView` runs them each time the node's
/// `EditorModel.shakeCount(of:)` goes up, and tests read the same timeline at a time of their choosing, so the motion is
/// pinned without a clock.
enum RefusalShake {
    /// How far the node moves to each side, in canvas points.
    static let distance = 6.0

    /// The offset's keyframes: out, across, home.
    @KeyframesBuilder<Double>
    static var keyframes: some Keyframes<Double> {
        KeyframeTrack {
            LinearKeyframe(distance, duration: 0.05)
            LinearKeyframe(-distance, duration: 0.1)
            LinearKeyframe(0, duration: 0.05)
        }
    }

    /// The same keyframes as a timeline, from rest.
    static var timeline: KeyframeTimeline<Double> {
        KeyframeTimeline(initialValue: 0.0) { keyframes }
    }

    /// The offset `seconds` after the shake starts.
    static func offset(at seconds: Double) -> Double {
        timeline.value(time: seconds)
    }

    /// How long the shake lasts, in seconds.
    static var duration: Double {
        timeline.duration
    }
}
