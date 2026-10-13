import CreatorGraph
import Foundation

/// Turns an `ImageReference` into a `GreyImage` for a node (fields spec §5): the picture kept in `GreyImageCache` when the
/// reference still points at what it did, else the bytes read through the evaluation's `ImageResolver` and decoded off the
/// calling actor by `GreyImageDecoder`.
///
/// A file that cannot be decoded (cut short, damaged, not PNG or JPEG) is remembered under its stamp and fails again at
/// once, without being read, until the stamp changes. Only what the bytes decide is remembered: a file that could not be
/// read (permissions, a network volume) is tried again at every evaluation, because fixing that changes no stamp.
enum ImageLoader {
    /// Decodes picture bytes; the default is `GreyImageDecoder.decode`, and a test passes one that counts its calls.
    typealias Decode = @Sendable (Data) async throws -> GreyImage

    static func image(for reference: ImageReference, resolver: ImageResolver, cache: GreyImageCache = .shared,
                      decode: Decode = { try await GreyImageDecoder.decode($0) }) async throws -> GreyImage {
        let stamp = resolver.stamp(of: reference)
        if let kept = cache.image(for: stamp) { return kept }
        if let known = cache.problem(for: stamp) { throw known }
        let data = try resolver.bytes(of: reference)
        let image: GreyImage
        do {
            image = try await decode(data)
        } catch let problem as ImageProblem {
            if stamp.isKeepable { cache.storeProblem(problem, for: stamp) }
            throw problem
        }
        if stamp.isKeepable { cache.store(image, for: stamp) }
        return image
    }
}
