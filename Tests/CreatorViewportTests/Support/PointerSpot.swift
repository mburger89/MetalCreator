import CreatorViewport

/// What the pointer is over, which a test changes while the model's pick closure reads it.
@MainActor
final class PointerSpot {
    var target: PickTarget?

    init(_ target: PickTarget?) {
        self.target = target
    }
}
