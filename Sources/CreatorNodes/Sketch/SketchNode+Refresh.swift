import CreatorGeometry
import CreatorGraph
import CreatorKernel
import CreatorSketch

extension SketchNode {
    /// `sketch` with each projected edge re-resolved against `references` exactly as the node does on every evaluation
    /// (`SketchProjections`): its curve is the picked edge's current projection onto `plane`, and it is suspended when its pick
    /// (in `settings`, under `NodeSetting.projection(reference)`) no longer finds exactly one edge. The sketch editor shows this,
    /// because the stored sketch keeps the curve a projection was made with and the node never writes the refresh back.
    public static func refreshingProjections(of sketch: Sketch, settings: [SocketName: ConstantValue], references: [Solid],
                                             on plane: Plane) -> Sketch {
        var refreshed = sketch
        _ = SketchProjections.resolve(&refreshed, settings: settings, references: references, on: plane)
        return refreshed
    }
}
