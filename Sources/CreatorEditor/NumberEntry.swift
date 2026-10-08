import MetalUI

/// A number field that commits on Return. While typing, the draft is kept locally so a partial
/// value ("6" on the way to "60") never reaches the graph; an unreadable entry is discarded.
/// With `clear`, an emptied field submits a clear instead (an optional input).
struct NumberEntry: Component {
    let text: String
    var placeholder = "Value"
    var width = 72.0
    var clear: (@MainActor () -> Void)?
    let commit: @MainActor (Double) -> Void
    @State var draft: String?

    var content: some ElementGroup {
        HStack(spacing: Pixels(0)) {
            TextField(placeholder, text: draft ?? text, onChange: { draft = $0 })
                .onSubmit {
                    if let draft {
                        if let clear, draft.trimmingCharacters(in: .whitespaces).isEmpty {
                            clear()
                        } else if let value = ValueText.parse(draft) {
                            commit(value)
                        }
                    }
                    draft = nil
                }
        }
        .frame(width: width.px)
        .onChange(of: text) { draft = nil }
    }
}
