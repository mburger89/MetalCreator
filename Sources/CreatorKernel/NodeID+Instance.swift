extension NodeID {
    /// Whether this is the identity a placed copy's tags name (patterns spec §6): a version-8 UUID, which
    /// `NodeID.instanceScoped` (CreatorGraph) makes and neither random IDs (version 4) nor group-scoped ones
    /// (`NodeID.scoped`, version 5) are. It is how a pick tells a tag of an instance from any other tag.
    public var isInstanceQualified: Bool { rawValue.uuid.6 >> 4 == 0x8 }
}
