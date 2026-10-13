/// How wide and tall a string draws in the labels' and chips' font (MetalUI's `.caption`), handed to the models by the
/// view that can ask the text system (`TextMeasure.init(_:)` in `TextMeasure+MetalUI.swift`, from the view's
/// `@Environment(\.textMeasurer)`; gap S5-c, MetalUI C23). The placement and collision logic stays in the models, which
/// take this as a parameter, so a unit test passes a deterministic one and a view test passes the real one.
/// There is no default and no fallback estimate: whoever places a label supplies a measure.
public struct TextMeasure {
    private let measure: @MainActor (String) -> ViewportSize

    public init(_ measure: @escaping @MainActor (String) -> ViewportSize) {
        self.measure = measure
    }

    /// The size `text` lays out at, unrounded, on one line.
    @MainActor
    public func callAsFunction(_ text: String) -> ViewportSize {
        measure(text)
    }
}
