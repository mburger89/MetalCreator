import MetalUI

extension ScreenPoint {
    /// A MetalUI gesture or hover location (element-local points, y down).
    public init(_ point: Point<Pixels>) {
        self.init(Double(point.x.value), Double(point.y.value))
    }
}
