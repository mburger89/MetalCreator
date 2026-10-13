import Foundation
import MetalUI
@testable import CreatorApp

/// A file picker that runs `whileOpen` while its panel is "open" (the person does something else), then answers.
@MainActor
final class InterruptedPicker: FilePicker {
    let answer: URL?
    let whileOpen: @MainActor () async -> Void

    init(answer: URL?, whileOpen: @escaping @MainActor () async -> Void) {
        self.answer = answer
        self.whileOpen = whileOpen
    }

    func chooseFileToOpen(_ types: [ContentType]) async throws -> URL? {
        await whileOpen()
        return answer
    }

    func chooseDestination(_ types: [ContentType], defaultName: String) async throws -> URL? {
        await whileOpen()
        return answer
    }
}
