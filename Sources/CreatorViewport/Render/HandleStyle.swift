/// Spec §6.5: a linear handle drags along an axis (Extrude distance). A radial one sets a radius or distance at an
/// edge (Fillet, Chamfer).
public enum HandleStyle: String, Hashable, Sendable {
    case linear
    case radial
}
