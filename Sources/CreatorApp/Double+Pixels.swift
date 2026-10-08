import MetalUI

extension Double {
    /// This layout length as MetalUI points.
    var px: Pixels { Pixels(Float(self)) }
}
