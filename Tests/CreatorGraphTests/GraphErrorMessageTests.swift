import CreatorKernel
import Testing
@testable import CreatorGraph

struct GraphErrorMessageTests {
    @Test func everyCaseHasItsSentence() {
        #expect(GraphError.nodeNotFound(NodeID()).message == "That node no longer exists.")
        #expect(GraphError.duplicateNode(NodeID()).message == "That node already exists.")
        #expect(GraphError.linkNotFound.message == "That wire no longer exists.")
        #expect(GraphError.parameterNotFound(ParameterID()).message == "That parameter no longer exists.")
        #expect(GraphError.invalidValue("Nope.").message == "Nope.")
        #expect(GraphError.invalidConnection(.sameNode).message == ConnectionProblem.sameNode.message)
    }
}
