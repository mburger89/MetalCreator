/// The exchange formats a kernel can read a solid model from (KiCad import, KI-2).
public enum SolidModelFormat: Sendable, Hashable {
    case step
    case iges
}
