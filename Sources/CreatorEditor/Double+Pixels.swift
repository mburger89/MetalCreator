import MetalUI

extension Double {
    /// This canvas length as MetalUI points. Canvas geometry is `Double`; MetalUI lengths are `Float`.
    var px: Pixels { Pixels(Float(self)) }
}
