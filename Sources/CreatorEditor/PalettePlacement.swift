import CreatorGeometry

/// Where the floating add-node palette goes in its window (spec §6.2: "at the cursor"): its top-left corner at the
/// pointer; flipped to the pointer's left when it would pass the window's right edge, and above it when it would pass
/// the bottom; clamped inside the window as a last resort, so it is always fully visible.
public enum PalettePlacement {
    /// The top-left corner, in window points, of a `size` palette opened at `pointer` in a `window`-sized window.
    /// Without a window size (the host hasn't placed the panel) it opens at the pointer.
    public static func origin(pointer: Vector2, size: Vector2, window: Vector2?,
                              margin: Double = PaletteLayout.windowMargin) -> Vector2 {
        guard let window else { return pointer }
        return Vector2(axis(pointer.x, size.x, window.x, margin), axis(pointer.y, size.y, window.y, margin))
    }

    /// One axis: after the pointer if it fits, else before it, then kept within the margins (the leading margin
    /// wins in a window smaller than the palette).
    private static func axis(_ pointer: Double, _ length: Double, _ window: Double, _ margin: Double) -> Double {
        let start = pointer + length > window - margin ? pointer - length : pointer
        return max(margin, min(start, window - margin - length))
    }
}
