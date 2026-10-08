import MetalUI

/// The keymap action behind every viewport key (`ViewportKeyBindings`).
public struct ViewportKeyAction: Action {
    public let command: ViewportKeyCommand

    public init(command: ViewportKeyCommand) {
        self.command = command
    }
}
