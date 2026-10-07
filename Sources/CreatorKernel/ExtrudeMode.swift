public enum ExtrudeMode: String, Sendable, Codable, CaseIterable {
    /// From the profile plane along its normal.
    case oneSided
    /// Half the distance on each side of the profile plane.
    case symmetric
}
