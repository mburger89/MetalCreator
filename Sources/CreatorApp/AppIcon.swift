import Foundation
import MetalUI

/// The window icon: the placeholder PNG in `Icon/`, the same file the Linux package installs for the desktop entry. SDL
/// applies it to every window (`App.icon`, MetalUI ruling AI-F). macOS keeps its bundle's icon and does not set it.
public enum AppIcon {
    /// The resource's name, without its extension.
    public static let name = "com.metalcreator.MetalCreator"

    /// The icon's bitmaps (one, 256 × 256); empty if the resource can't be found or decoded.
    public static func bitmaps() -> [ImageBitmap] {
        ImageBitmap(resource: name, subdirectory: "Icon", bundle: resourceBundle()).map { [$0] } ?? []
    }

    /// CreatorApp's resource bundle: beside the executable in a package (Linux, Windows), where SwiftPM puts it; otherwise,
    /// in a build tree, the one SwiftPM's accessor finds. A package has no build tree, so the accessor, which traps when it
    /// finds nothing, is only reached where the bundle is.
    private static func resourceBundle() -> Bundle {
        let beside = Bundle.main.executableURL?.deletingLastPathComponent().appending(path: "MetalCreator_CreatorApp.bundle")
        return beside.flatMap { Bundle(url: $0) } ?? Bundle.module
    }
}
