import Testing
@testable import CreatorApp

struct AppIconTests {
    @Test func theBundledIconLoadsAsANonEmptyBitmap() throws {
        let bitmaps = AppIcon.bitmaps()
        let icon = try #require(bitmaps.first, "the icon resource is in CreatorApp's bundle and decodes")
        #expect(bitmaps.count == 1)
        #expect(icon.width == 256 && icon.height == 256)
    }
}
