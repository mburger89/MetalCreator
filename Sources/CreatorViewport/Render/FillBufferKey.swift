/// What the renderer's fill buffer is built from. Fills don't depend on the camera, so a pan or a zoom keeps the buffer.
struct FillBufferKey: Equatable {
    var fills: [OverlayFill]
    var palette: ViewportPalette
}
