/// `Field` is `Hashable` (7b-3 keys previews by it), so a picture must be too. Equality compares the pixels (an array
/// comparison that returns at once for two copies sharing storage, which is what a field copied around is). Hashing must not
/// read up to 64 million pixels each time, so it takes the size and a fixed sample of pixels: equal pictures still hash equal.
extension GreyImage: Hashable {
    public static func == (lhs: GreyImage, rhs: GreyImage) -> Bool {
        lhs.width == rhs.width && lhs.height == rhs.height && lhs.pixels == rhs.pixels
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(width)
        hasher.combine(height)
        let step = max(1, pixels.count / 64)
        for index in stride(from: 0, to: pixels.count, by: step) {
            hasher.combine(pixels[index])
        }
    }
}
