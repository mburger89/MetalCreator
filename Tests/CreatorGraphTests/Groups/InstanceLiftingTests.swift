import CreatorKernel
import Testing
@testable import CreatorGraph

/// The copies a pattern node places are named by the node and the tool's tag nodes (`NodeID.instanceScoped`), so a table
/// that renames nodes (a group instance's, `EvaluationScope.entering`) needs the pairs renamed too.
struct InstanceLiftingTests {
    let placer = NodeID(), tool = NodeID(), otherPlacer = NodeID()
    let newPlacer = NodeID(), newTool = NodeID()

    @Test func liftingAddsTheCopiesAPlacerMadeToTheTable() {
        let names = [placer: newPlacer, tool: newTool, otherPlacer: NodeID()]
        let lifted = GroupScopes.lifting(names, placers: [placer])
        #expect(lifted[placer] == newPlacer)
        #expect(lifted[NodeID.instanceScoped([placer, tool])] == NodeID.instanceScoped([newPlacer, newTool]))
        #expect(lifted[NodeID.instanceScoped([placer, placer])] == NodeID.instanceScoped([newPlacer, newPlacer]))
        #expect(lifted[NodeID.instanceScoped([otherPlacer, tool])] == nil)
    }

    @Test func noPlacersLeavesTheTableAsItIs() {
        let names = [placer: newPlacer, tool: newTool]
        #expect(GroupScopes.lifting(names, placers: []) == names)
    }

    @Test func aPlacerTheTableDoesNotRenameAddsNothing() {
        #expect(GroupScopes.lifting([tool: newTool], placers: [placer]) == [tool: newTool])
    }
}
