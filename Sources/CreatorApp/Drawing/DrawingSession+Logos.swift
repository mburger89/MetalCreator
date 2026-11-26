import CreatorDrawing
import CreatorGraph
import CreatorNodes
import Foundation

/// The title block's logo in the app (DR-5 R11, R12): a picture a person or a template supplied, so untrusted. Its bytes are checked
/// before a pixel is decoded, decoded off the main actor over white, converted to 8 bits and cached by the hash of the bytes.
extension DrawingSession {
    /// Turns a logo file's bytes into a grey picture; replaced by tests that need to see the decode suspend.
    typealias LogoDecoder = @Sendable (Data) async throws -> GreyImage

    static let defaultLogoDecoder: LogoDecoder = { try await GreyImageDecoder.decode($0, background: .white) }

    /// Why `data` can't be a logo, as a sentence, or `nil` when it can: its size, its format and header, then its sides.
    nonisolated static func logoProblem(in data: Data) -> String? {
        guard data.count <= LogoLimits.maximumBytes else { return LogoLimits.fileTooLargeSentence }
        do {
            let info = try GreyImageDecoder.inspect(data)
            return LogoLimits.sideSentence(width: info.width, height: info.height)
        } catch {
            return error.logoSentence
        }
    }

    /// The logo of `hash`, if it has been decoded (or has failed to be).
    func decodedLogo(forHash hash: String) -> LogoFact? {
        if let known = logoCache[hash] { return known }
        startLogoDecode(hash)
        return nil
    }

    /// The logo of `hash`, decoded now if it hasn't been.
    public func logo(forHash hash: String) async -> LogoFact {
        if let known = logoCache[hash] { return known }
        if let task = startLogoDecode(hash) { await task.value }
        return logoCache[hash] ?? .unreadable("The decoding was cancelled.")
    }

    /// Checks and decodes the bytes of a logo a person is about to use (they are not in the document yet): the sentence that
    /// refuses them, or `nil` when they make a picture. Cached under their hash, so the sheet that takes them shows them at once.
    func vetLogo(_ data: Data) async -> String? {
        let hash = ImageHash(of: data).hex
        if let known = logoCache[hash] {
            if case .unreadable(let reason) = known { return reason }
            return nil
        }
        let fact = await Self.makeLogo(data, key: hash, decoder: logoDecoder)
        guard let fact else { return "The decoding was cancelled." }
        if case .unreadable(let reason) = fact { return reason }
        logoCache[hash] = fact
        return nil
    }

    @discardableResult
    private func startLogoDecode(_ hash: String) -> Task<Void, Never>? {
        if let running = logoTasks[hash] { return running }
        guard let digest = ImageHash(hex: hash), let data = document.images[digest] else {
            logoCache[hash] = .unreadable("The picture isn't in this document.")
            return nil
        }
        let decoder = logoDecoder
        let task = Task { @MainActor [weak self] in
            let fact = await Self.makeLogo(data, key: hash, decoder: decoder)
            guard let self else { return }
            self.logoTasks[hash] = nil
            guard let fact, !Task.isCancelled else { return }
            self.logoCache[hash] = fact
            self.publishFacts()
        }
        logoTasks[hash] = task
        return task
    }

    /// The decoded logo, or why it can't be one; `nil` when the work was cancelled. Off the main actor.
    @concurrent
    nonisolated static func makeLogo(_ data: Data, key: String, decoder: LogoDecoder) async -> LogoFact? {
        if let problem = logoProblem(in: data) { return .unreadable(problem) }
        do {
            let image = try await decoder(data)
            // 16 bits to 8, rounded: (v + 128) / 257 (R11).
            let bytes = image.pixels.map { UInt8(truncatingIfNeeded: (Int($0) + 128) / 257) }
            guard let pixels = GreyPixels(key: key, width: image.width, height: image.height, bytes: bytes) else {
                return .unreadable(ImageProblem.undecodable.message)
            }
            return .picture(pixels)
        } catch is CancellationError {
            return nil
        } catch {
            return .unreadable(error.logoSentence)
        }
    }
}

private extension Error {
    /// An image problem's sentence, or the system's.
    var logoSentence: String { (self as? ImageProblem)?.message ?? localizedDescription }
}
