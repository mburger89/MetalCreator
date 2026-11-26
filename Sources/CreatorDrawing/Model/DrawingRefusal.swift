/// Why a drawing edit was refused: a full sentence in the app's voice.
public struct DrawingRefusal: Error, Hashable, Sendable {
    public var sentence: String

    public init(sentence: String) {
        self.sentence = sentence
    }
}
