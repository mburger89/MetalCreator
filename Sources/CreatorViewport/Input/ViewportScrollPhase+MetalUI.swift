import MetalUI

extension ViewportScrollPhase {
    /// The phase of a MetalUI scroll event. Momentum wins over the gesture phase; no phase at all is a wheel step.
    public init(_ event: ScrollEvent) {
        if event.isMomentum {
            self = .momentum
            return
        }
        switch event.phase {
        case .none: self = .step
        case .mayBegin, .began, .changed: self = .moving
        case .ended, .cancelled: self = .ended
        }
    }
}
