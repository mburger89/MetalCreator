/// What a group definition shows on the outside: its name, accent and sockets (groups spec §4).
/// `GraphCommand.setInterface` replaces it as one step; the inside is edited with `GraphCommand.inDefinition`.
public struct GroupInterface: Sendable, Equatable {
    public var name: String
    public var accent: AccentRole
    /// The group node's inputs, which are Group Input's outputs. Ordered; names unique.
    public var inputs: [SocketSpec]
    /// The group node's outputs, which are Group Output's inputs. Ordered; names unique.
    public var outputs: [SocketSpec]

    public init(name: String, accent: AccentRole, inputs: [SocketSpec], outputs: [SocketSpec]) {
        self.name = name
        self.accent = accent
        self.inputs = inputs
        self.outputs = outputs
    }
}
