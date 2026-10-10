import Foundation
import MetalUI

/// The part of a MetalUI `Window` that shows the document: its title, AppKit's edited dot in the close button and the
/// represented file (the proxy icon). `Window` is one; tests use a recorder.
@MainActor
public protocol WindowChrome: AnyObject {
    var title: String { get set }
    var isDocumentEdited: Bool { get set }
    var representedURL: URL? { get set }
}

extension Window: WindowChrome {}
