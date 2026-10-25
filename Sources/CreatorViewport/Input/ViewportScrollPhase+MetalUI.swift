import MetalUI

extension ViewportScrollPhase {
    /// The phase of a MetalUI scroll event. Momentum wins over the gesture phase. A trackpad is told from a wheel by
    /// `isPrecise` (a wheel's delta is lines x 10, a trackpad's is points), falling back to the gesture phase: an
    /// event with a phase is a trackpad's. SDL reports neither (always imprecise, no phases), so there every scroll is
    /// a wheel step and zooms (a MetalUI gap, docs/metalui-gaps.md).
    public init(_ event: ScrollEvent) {
        switch event.momentumPhase {
        case .none: break
        case .ended, .cancelled:
            self = .momentumEnded
            return
        case .mayBegin, .began, .changed:
            self = .momentum
            return
        }
        switch event.phase {
        case .none: self = event.isPrecise ? .preciseStep : .step
        case .mayBegin, .began, .changed: self = .moving
        case .ended: self = .ended
        case .cancelled: self = .cancelled
        }
    }
}
