import MetalUI

extension ViewportScrollPhase {
    /// The phase of a MetalUI scroll event. Momentum wins over the gesture phase. A trackpad is told from a wheel by
    /// `isPrecise` (a wheel's delta is lines x 10, a trackpad's is points), falling back to the gesture phase: an
    /// event with a phase is a trackpad's. SDL synthesizes both (MetalUI XP-G28, caveats 845 and 846): `isPrecise` for
    /// a fractional delta or an open stream, `.began`/`.changed` phases and a zero-delta `.ended` about 0.15 s after
    /// the last event. A notched wheel stays imprecise with no phase and zooms. There is no momentum on SDL, and a
    /// high-resolution wheel reads as precise (caveat 845).
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
