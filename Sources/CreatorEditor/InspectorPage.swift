/// Everything the context inspector shows: the selected node's header and sections (when
/// exactly one node is selected), then the document parameters, which are always listed.
public struct InspectorPage: Equatable, Sendable {
    public var header: InspectorHeader?
    public var sections: [InspectorSectionRows]
    public var parameters: [ParameterRow]
    /// The selected comments' page: set when comments are selected and no node is (`EditorModel.inspectorPage`).
    public var comment: CommentPage?
}
