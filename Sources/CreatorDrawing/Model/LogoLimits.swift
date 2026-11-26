import CreatorKernel
import Foundation

/// What a title block logo may be (DR-5 R11): the file's size and the picture's sides. A logo is untrusted input.
public enum LogoLimits {
    /// 2 MiB.
    public static let maximumBytes = 2_097_152
    public static let maximumSide = 1024

    public static let fileTooLargeSentence = "A logo file is at most 2 MB."

    /// The sentence for a picture too big on a side, or nil when it fits.
    public static func sideSentence(width: Int, height: Int) -> String? {
        guard width > maximumSide || height > maximumSide else { return nil }
        let w = width.formatted(.number.locale(.messages)), h = height.formatted(.number.locale(.messages))
        let most = maximumSide.formatted(.number.locale(.messages))
        return "A logo is at most \(most) pixels on a side; this picture is \(w) × \(h)."
    }
}
