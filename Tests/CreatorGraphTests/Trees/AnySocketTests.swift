import Testing
@testable import CreatorGraph

struct AnySocketTests {
    @Test func anAnySocketAcceptsEveryTypeAndIsAcceptedByEvery() {
        for type in SocketType.allCases {
            #expect(SocketType.any.accepts(type), "any accepts \(type)")
            #expect(type.accepts(.any), "\(type) accepts any")
        }
    }

    @Test func theExistingConversionsAreUnchanged() {
        #expect(SocketType.number.accepts(.integer))
        #expect(!SocketType.integer.accepts(.number))
        #expect(SocketType.plane.accepts(.vector))
        #expect(!SocketType.solid.accepts(.profile))
    }

    @Test func anyKeepsItsItemsWhateverTheyAre() {
        #expect(Value.list([.integer(1), .bool(true)]).converted(to: .any)?.items.count == 2)
        #expect(Scalar.bool(true).converted(to: .any) != nil)
    }

    @Test func anyIsNamedAValue() {
        #expect(SocketType.any.indefiniteName == "a value")
    }

    @Test func listsAndTreesIsACategoryBeforeOutput() {
        #expect(NodeCategory.lists.title == "Lists & Trees")
        #expect(NodeCategory.value.title == "Value")
        #expect(NodeCategory.allCases.last == .output)
        #expect(NodeCategory.allCases.firstIndex(of: .lists) == NodeCategory.allCases.firstIndex(of: .feature).map { $0 + 1 })
    }
}
