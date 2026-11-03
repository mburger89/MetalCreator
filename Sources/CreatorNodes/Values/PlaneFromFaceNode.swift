import CreatorGeometry
import CreatorGraph
import CreatorKernel

/// A plane on a flat face of a solid (sketcher spec §7): origin at the face centroid, normal along the
/// face's outward normal, x axis from `FacePlane`. The face is the remembered `FacePick` in the `face`
/// setting, so the plane follows the face when the model changes, and, when the face was one a union merged
/// with another operand's and the faces have since come apart, it stays on the part that is left
/// (`Topology.resolution(of:)`). "New sketch on face" (S5) wires this
/// node into a Sketch.
public enum PlaneFromFaceNode: NodeDefinition {
    public static let typeID = "creator.planeFromFace"
    public static let displayName = "Plane from Face"
    public static let category = NodeCategory.value
    public static let inputs = [SocketSpec("solid", .solid)]
    public static let outputs = [SocketSpec("plane", .plane)]

    static let nothingPicked = "Pick a face for this plane to sit on."
    static let unreadablePick = "This plane's picked face can't be read. Pick the face again."
    static let noMatch = "The picked face isn't on this solid any more. Pick it again."
    static let notFlat = "The picked face isn't flat, so it has no plane."
    static let unnamedPick = FacePickWording.unnamed("plane")

    static let mergedPick = FacePickWording.merged("The plane sits on")

    public static func evaluate(_ inputs: NodeInputs, kernel: any Kernel, context: EvalContext) async throws -> NodeOutputs {
        let solid = try inputs.solid("solid")
        let pick: FacePick
        switch context.node.inputValues[NodeSetting.face] {
        case nil: throw NodeError.invalidValue(nothingPicked)
        case .facePick(let stored)?: pick = stored
        case .some: throw NodeError.invalidValue(unreadablePick)
        }
        // A pick on a placed copy that the pattern no longer has is not retried on the part around it (patterns spec §6).
        if let gone = solid.topology.vanishedInstances(in: pick.tags).first {
            throw NodeError.invalidValue("Instance \(InstancePath.text(gone)) no longer exists, so the picked face isn't there any more. "
                + "Pick the face again.")
        }
        let resolution = solid.topology.resolution(of: pick)
        let matches = resolution.faces
        guard let face = matches.first else { throw NodeError.invalidValue(noMatch) }
        guard face.kind == .plane, let normal = face.normal?.normalized else { throw NodeError.invalidValue(notFlat) }
        var warnings: [String] = []
        if resolution.isAmbiguous {
            warnings.append(mergedPick)
        } else if matches.count > 1 {
            warnings.append(FacePickWording.several(matches.count, "the plane is on"))
        }
        if pick.touchesUnnamedFace { warnings.append(unnamedPick) }
        return NodeOutputs(["plane": .plane(FacePlane.plane(origin: face.centroid, normal: normal))], warnings: warnings)
    }

    /// The plane `evaluate` puts on a flat face that has a normal (its centroid and `FacePlane`'s axes); `nil` for any
    /// other face. The sketch editor opens a new sketch on it before this node has run. (`evaluate` is left as it is, so
    /// the naming-face-picks track's edits to it merge; `NewSketchOnFaceTests` pins that the two agree.)
    public static func plane(of face: FaceInfo) -> Plane? {
        guard face.kind == .plane, let normal = face.normal?.normalized else { return nil }
        return FacePlane.plane(origin: face.centroid, normal: normal)
    }
}
