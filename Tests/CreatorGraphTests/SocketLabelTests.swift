import Testing
@testable import CreatorGraph

struct SocketLabelTests {
    @Test func splitsCamelCase() {
        #expect(SocketLabel.text(for: "cornerRadius") == "Corner radius")
        #expect(SocketLabel.text(for: "width") == "Width")
        #expect(SocketLabel.text(for: "holeCountX") == "Hole count x")
        #expect(SocketLabel.text(for: "x") == "X")
        #expect(SocketLabel.text(for: "") == "")
    }
}
