import MetalUI

extension Double {
    /// This layout length as MetalUI points. Layout numbers are `Double`; MetalUI lengths are `Float`.
    var px: Pixels { Pixels(Float(self)) }
}
