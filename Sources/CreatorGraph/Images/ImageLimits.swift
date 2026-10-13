/// What an image may be (fields spec D10). Images are untrusted input: a file is checked against these before anything is
/// decoded, so a hostile or mistaken file costs a message, not the machine's memory.
public enum ImageLimits {
    /// The most bytes a PNG or JPEG file may have: 16 MB.
    public static let maxBytes = 16 * 1024 * 1024
    /// The most pixels either side may have.
    public static let maxSide = 8192
}
