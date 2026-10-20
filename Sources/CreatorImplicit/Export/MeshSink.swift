/// Where a streamed export puts its triangles (implicit spec Errata D12): one window at a time, never the whole mesh. An STL sink
/// writes the triangles as they come; a 3MF sink writes the vertices and the triangles of each object to files of their own and
/// puts them in the zip at the end. `beginObject` names what the following windows are (3MF: an `<object>`; STL has one body).
public protocol MeshSink {
    /// Triangles added to the file so far.
    var triangleCount: Int { get }
    /// Vertices added to the current object so far: the number the next independent mesh's vertices start at.
    var vertexCount: Int { get }
    mutating func beginObject(name: String) throws
    mutating func add(_ window: MeshWindow) throws
    mutating func endObject() throws
    /// Completes the file and puts it at its destination.
    mutating func finish() throws
    /// Throws away what was written.
    mutating func cancel()
}
