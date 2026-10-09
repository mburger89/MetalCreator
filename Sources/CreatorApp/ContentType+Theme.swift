import MetalUI

extension ContentType {
    /// A MetalCreator colour theme (Themes milestone): small JSON, saved as `.mctheme`. Not registered with the
    /// system, so the file panels match it by extension.
    public static let mctheme = ContentType("com.metalcreator.mctheme", conformingTo: [.json], filenameExtensions: ["mctheme"])
}
