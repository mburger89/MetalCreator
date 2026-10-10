/// Everything the context inspector shows: the selected node's header and sections (when
/// exactly one node is selected), then the document parameters, which are always listed.
public struct InspectorPage: Equatable, Sendable {
    public var header: InspectorHeader?
    public var sections: [InspectorSectionRows]
    public var parameters: [ParameterRow]
    /// The definition behind the selected group node, Group Input or Group Output (`EditorModel.groupPanel`).
    public var group: GroupPanel?
}
