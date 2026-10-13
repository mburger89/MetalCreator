import MetalUI

extension TextMeasure {
    /// A measure over MetalUI's text system (MetalUI C23, `@Environment(\.textMeasurer)`): the size a `ProposalText` in the
    /// `.caption` font, which is what every label and chip is drawn in, lays out at with no wrapping. It is read from the
    /// environment of the element that builds the labels, so a font or theme change in that environment reaches it.
    @MainActor
    public init(_ measurer: TextMeasurer) {
        self.init { text in
            let size = measurer.resolve(ProposalText(text).font(.caption))
                .measure(in: Size(width: .infinity, height: .infinity))
            return ViewportSize(width: Double(size.width.value), height: Double(size.height.value))
        }
    }
}
