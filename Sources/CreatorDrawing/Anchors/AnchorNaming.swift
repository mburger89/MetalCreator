import CreatorKernel

public enum AnchorNaming {
    /// A tag set is lasting (plan R3) when it is not empty and none of its tags is unstable (an `.unnamed` OCCT face number, or a
    /// blend of one), which a rebuild renumbers.
    public static func isLasting(_ tags: Set<TopoTag>) -> Bool {
        !tags.isEmpty && !tags.contains { $0.role.isUnstable }
    }
}
