import CreatorGraph
import Foundation
import Synchronization
import Testing
@testable import CreatorNodes

/// `GreyImageCache` and `ImageLoader`: decoded pictures are kept by what they were read from, and evicted least recently used.
struct GreyImageCacheTests {
    func picture(_ pixels: Int, value: UInt16 = 7) throws -> GreyImage {
        try #require(GreyImage(width: pixels, height: 1, pixels: [UInt16](repeating: value, count: pixels)))
    }

    func stamp(_ name: String) -> ImageStamp { .file(path: "/\(name)", modified: Date(timeIntervalSince1970: 1), size: 1) }

    @Test func aStoredPictureComesBackAndAnotherKeyMisses() throws {
        let cache = GreyImageCache(budgetBytes: 1_000)
        try cache.store(picture(10), for: stamp("a"))
        #expect(cache.image(for: stamp("a"))?.width == 10)
        #expect(cache.image(for: stamp("b")) == nil)
        let later = ImageStamp.file(path: "/a", modified: Date(timeIntervalSince1970: 2), size: 1)
        #expect(cache.image(for: later) == nil, "the file was modified: a different key")
    }

    @Test func theLeastRecentlyUsedPictureGoesFirstWhenOverBudget() throws {
        let cache = GreyImageCache(budgetBytes: 100)  // room for five 10-pixel pictures of 20 bytes
        for name in ["a", "b", "c", "d", "e"] { try cache.store(picture(10), for: stamp(name)) }
        #expect(cache.count == 5)
        _ = cache.image(for: stamp("a"))  // a is now the most recently used
        try cache.store(picture(10), for: stamp("f"))
        #expect(cache.count == 5)
        #expect(cache.image(for: stamp("a")) != nil && cache.image(for: stamp("f")) != nil)
        #expect(cache.image(for: stamp("b")) == nil, "b was the oldest")
    }

    @Test func aPictureBiggerThanTheWholeBudgetIsNotKept() throws {
        let cache = GreyImageCache(budgetBytes: 100)
        try cache.store(picture(60), for: stamp("big"))
        #expect(cache.count == 0)
    }

    @Test func theLoaderDecodesOnceAndReusesThePictureUntilTheStampChanges() async throws {
        let folder = TempFolderForNodes()
        let cache = GreyImageCache(budgetBytes: 1_000_000)
        let file = try folder.write(TestImages.flatGrey(4, 4, 100), to: "a.png")
        try folder.touch(file, Date(timeIntervalSince1970: 1_000))
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        let resolver = ImageResolver()
        let first = try await ImageLoader.image(for: reference, resolver: resolver, cache: cache)
        #expect(first.pixels.allSatisfy { $0 == 100 * 257 } && cache.count == 1)
        // Replace the bytes but keep size and date: the stamp cannot tell, so the kept picture is used (D11's rule is the date).
        try folder.write(TestImages.flatGrey(4, 4, 200), to: "a.png")
        try folder.touch(file, Date(timeIntervalSince1970: 1_000))
        #expect(try await ImageLoader.image(for: reference, resolver: resolver, cache: cache).pixels[0] == 100 * 257)
        try folder.touch(file, Date(timeIntervalSince1970: 2_000))
        #expect(try await ImageLoader.image(for: reference, resolver: resolver, cache: cache).pixels[0] == 200 * 257)
        #expect(cache.count == 2)
    }

    @Test func aMissingOrBadImageIsAProblemAndNothingIsKept() async throws {
        let cache = GreyImageCache(budgetBytes: 1_000_000)
        let gone = ImageReference.linked(relativePath: nil, absolutePath: "/no/such/dir/x.png")
        await #expect(throws: ImageProblem.notFound(name: "x.png", folder: "/no/such/dir/")) {
            try await ImageLoader.image(for: gone, resolver: ImageResolver(), cache: cache)
        }
        let junk = Data("not a picture".utf8)
        await #expect(throws: ImageProblem.undecodable) {
            let hash = ImageHash(of: junk)
            return try await ImageLoader.image(for: .embedded(hash), resolver: ImageResolver(embedded: [hash: junk]), cache: cache)
        }
        #expect(cache.count == 0)
    }

    // MARK: Pictures that cannot be decoded

    /// A decoder that counts its calls, so a test can see when the loader decodes and when it does not.
    final class CountingDecoder: Sendable {
        private let calls = Mutex(0)
        var count: Int { calls.withLock { $0 } }

        var decode: ImageLoader.Decode {
            { data in
                self.calls.withLock { $0 += 1 }
                return try await GreyImageDecoder.decode(data)
            }
        }
    }

    @Test func aDamagedFileIsDecodedOnceAndThenFailsAtOnceUntilItChanges() async throws {
        let folder = TempFolderForNodes()
        let cache = GreyImageCache(budgetBytes: 1_000_000)
        let counter = CountingDecoder()
        let whole = TestImages.noisy(64)
        let file = try folder.write(whole.prefix(whole.count / 2), to: "cut.png")
        try folder.touch(file, Date(timeIntervalSince1970: 1_000))
        let reference = ImageReference.linked(relativePath: nil, absolutePath: file.path(percentEncoded: false))
        for _ in 0..<3 {
            await #expect(throws: ImageProblem.undecodable) {
                try await ImageLoader.image(for: reference, resolver: ImageResolver(), cache: cache, decode: counter.decode)
            }
        }
        #expect(counter.count == 1, "the cut-short JPEG was read and decoded once; the next two evaluations failed from memory")
        #expect(cache.problemCount == 1 && cache.count == 0)
        // Saving the whole picture changes the file's date and size, so the stamp changes and the file is tried again.
        try folder.write(whole, to: "cut.png")
        try folder.touch(file, Date(timeIntervalSince1970: 2_000))
        let image = try await ImageLoader.image(for: reference, resolver: ImageResolver(), cache: cache, decode: counter.decode)
        #expect(counter.count == 2 && image.width == 64)
    }

    @Test func aDamagedEmbeddedPictureIsRememberedByItsHash() async throws {
        let cache = GreyImageCache(budgetBytes: 1_000_000)
        let counter = CountingDecoder()
        let png = TestImages.noisy(32)
        let damaged = Data(png.prefix(png.count / 2))
        let hash = ImageHash(of: damaged)
        let resolver = ImageResolver(embedded: [hash: damaged])
        for _ in 0..<2 {
            await #expect(throws: ImageProblem.undecodable) {
                try await ImageLoader.image(for: .embedded(hash), resolver: resolver, cache: cache, decode: counter.decode)
            }
        }
        #expect(counter.count == 1)
    }

    /// Whether a file with no permissions is really unreadable here: not as root (a CI container's user), and not on Windows.
    private static let canDenyReading: Bool = {
        #if os(Windows)
        false
        #else
        geteuid() != 0
        #endif
    }()

    @Test(.enabled(if: canDenyReading, "root and Windows read a file whose permissions are 000"))
    func aFileThatCouldNotBeReadIsTriedAgainBecauseFixingThatChangesNoStamp() async throws {
        let folder = TempFolderForNodes()
        let cache = GreyImageCache(budgetBytes: 1_000_000)
        let counter = CountingDecoder()
        let file = try folder.write(TestImages.flatGrey(4, 4, 90), to: "locked.png")
        let path = file.path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path) }
        let reference = ImageReference.linked(relativePath: nil, absolutePath: path)
        await #expect(throws: ImageProblem.self) {
            try await ImageLoader.image(for: reference, resolver: ImageResolver(), cache: cache, decode: counter.decode)
        }
        #expect(cache.problemCount == 0, "a read error is not remembered")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        let image = try await ImageLoader.image(for: reference, resolver: ImageResolver(), cache: cache, decode: counter.decode)
        #expect(image.pixels.allSatisfy { $0 == 90 * 257 })
    }

    @Test func theRememberedProblemsAreBoundedAndTheOldestGoFirst() {
        let cache = GreyImageCache(budgetBytes: 1_000)
        for index in 0..<(GreyImageCache.maxProblems + 10) { cache.storeProblem(.undecodable, for: stamp("p\(index)")) }
        #expect(cache.problemCount == GreyImageCache.maxProblems)
        #expect(cache.problem(for: stamp("p0")) == nil && cache.problem(for: stamp("p\(GreyImageCache.maxProblems + 9)")) == .undecodable)
    }
}
