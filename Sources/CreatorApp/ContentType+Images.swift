import MetalUI

extension ContentType {
    /// A PNG picture, one of the two formats an Image Field reads (fields spec §5). Matched by extension in the file panels.
    public static let png = ContentType("public.png", conformingTo: [.data], filenameExtensions: ["png"],
                                       localizedDescription: "PNG image")
    /// A JPEG picture.
    public static let jpeg = ContentType("public.jpeg", conformingTo: [.data], filenameExtensions: ["jpg", "jpeg"],
                                        localizedDescription: "JPEG image")
}
