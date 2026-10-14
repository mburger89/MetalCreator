import CreatorGeometry
import Testing
@testable import CreatorGraph

/// The implicit and mesh socket types, their values and conversions (implicit spec §2.1 to §2.3).
struct ImplicitValueTests {
    @Test func implicitSocketsAcceptOnlyImplicitsAndAny() {
        for source in SocketType.allCases {
            let expected = source == .implicit || source == .any
            #expect(SocketType.implicit.accepts(source) == expected, "implicit accepts \(source)")
        }
    }

    @Test func aMeshSocketAcceptsMeshesImplicitsAndAny() {
        for source in SocketType.allCases {
            let expected = source == .mesh || source == .implicit || source == .any
            #expect(SocketType.mesh.accepts(source) == expected, "mesh accepts \(source)")
        }
    }

    @Test func aFieldSocketAcceptsAnImplicitAndNothingElseAcceptsAMeshOrAField() {
        #expect(SocketType.field.accepts(.implicit))
        #expect(!SocketType.field.accepts(.mesh))
        for type in SocketType.allCases where type != .any && type != .mesh {
            #expect(!type.accepts(.mesh), "\(type) must not accept a mesh")
        }
        for type in SocketType.allCases where type != .any && type != .field {
            #expect(!type.accepts(.field), "\(type) must not accept a field")
        }
        #expect(!SocketType.solid.accepts(.implicit) && !SocketType.implicit.accepts(.solid) && !SocketType.implicit.accepts(.field))
        #expect(!SocketType.number.accepts(.implicit) && !SocketType.implicit.accepts(.mesh) && !SocketType.mesh.accepts(.solid))
    }

    @Test func theTypesHaveTheirIndefiniteNames() {
        #expect(SocketType.implicit.indefiniteName == "an implicit solid")
        #expect(SocketType.mesh.indefiniteName == "a mesh")
    }

    @Test func scalarsReportTheirTypes() {
        #expect(Scalar.implicit(StubImplicit(radius: 5).reference).type == .implicit)
        #expect(Scalar.mesh(StubMesh(triangleCount: 4)).type == .mesh)
    }

    @Test func anImplicitConvertsToAFieldThatIsItsDistance() throws {
        let solid = StubImplicit(radius: 5).reference
        let converted = try #require(Scalar.implicit(solid).converted(to: .field))
        guard case .field(let field) = converted else { Issue.record("not a field"); return }
        #expect(field == .implicit(solid))
        #expect(field.description == "implicit(stub(radius 5.0))")
        #expect(field.isSignedDistance && field.unit == .millimetres && !field.measuresWithKernel)
        #expect(field.children.isEmpty && field.ownPlane == nil)
    }

    @Test func anImplicitPassesToAMeshSocketUnchangedAndConvertsToNothingElse() throws {
        let scalar = Scalar.implicit(StubImplicit(radius: 5).reference)
        #expect(scalar.converted(to: .mesh)?.type == .implicit, "the node that takes it meshes it")
        for target in SocketType.allCases where ![.implicit, .field, .mesh, .any].contains(target) {
            #expect(scalar.converted(to: target) == nil, "an implicit is not \(target)")
        }
        #expect(Scalar.mesh(StubMesh(triangleCount: 1)).converted(to: .implicit) == nil)
        #expect(Scalar.mesh(StubMesh(triangleCount: 1)).converted(to: .field) == nil)
        #expect(Value.list([scalar, scalar]).converted(to: .field)?.items.count == 2)
    }

    @Test func implicitLeavesAreEqualWhenTheirSolidsAre() {
        #expect(Field.implicit(StubImplicit(radius: 5).reference) == .implicit(StubImplicit(radius: 5).reference))
        #expect(Field.implicit(StubImplicit(radius: 5).reference) != .implicit(StubImplicit(radius: 6).reference))
        #expect(Set([Field.implicit(StubImplicit(radius: 5).reference), .implicit(StubImplicit(radius: 5).reference)]).count == 1)
    }

    @Test func sizesFollowTheSpec() {
        let leaf = Field.implicit(StubImplicit(radius: 5).reference)
        #expect(leaf.nodeCount == 1 && leaf.estimatedBytes == 64 + 32 + 96)
        #expect(Scalar.implicit(StubImplicit(radius: 5).reference).estimatedBytes == 96)
        #expect(Scalar.mesh(StubMesh(triangleCount: 10)).estimatedBytes == 16 * 30 + 120)
    }

    @Test func nodeInputsReadAnImplicit() throws {
        let solid = StubImplicit(radius: 5).reference
        let inputs = NodeInputs(item: 0, slots: ["shape": .item(.implicit(solid)), "n": .item(.number(1))])
        #expect(try inputs.implicit("shape") == solid)
        #expect(throws: NodeError.typeMismatch("n", expected: .implicit)) { try inputs.implicit("n") }
    }

    @Test func theCategoriesComeAfterFieldsAndBeforeOutput() {
        #expect(NodeCategory.implicit.title == "Implicit" && NodeCategory.mesh.title == "Mesh")
        #expect(NodeCategory.allCases.suffix(4) == [.fields, .implicit, .mesh, .output])
    }
}

/// What tooltips and the inspector say about implicit solids (implicit spec §2.1).
struct ImplicitSummaryTests {
    @Test func oneSolidShowsItsRecipeCutToTheLimit() {
        let one = Value.one(.implicit(StubImplicit(radius: 5).reference))
        #expect(one.implicitSummary() == "stub(radius 5.0)")
        #expect(one.implicitSummary(limit: 8) == "stub(ra…")
        #expect(one.implicitSummary(limit: 80) == "stub(radius 5.0)")
    }

    @Test func severalSolidsAreCounted() {
        let list = Value.list([.implicit(StubImplicit(radius: 1).reference), .implicit(StubImplicit(radius: 2).reference)])
        #expect(list.implicitSummary() == "2 implicit solids")
    }

    @Test func anythingElseHasNoSummary() {
        #expect(Value.one(.number(1)).implicitSummary() == nil)
        #expect(Value.list([]).implicitSummary() == nil)
        #expect(Value.list([.implicit(StubImplicit(radius: 1).reference), .number(2)]).implicitSummary() == nil)
    }

    @Test func aPayloadHasNoFactsUnlessItSaysSo() {
        #expect(StubImplicit(radius: 1).inspectorFacts.isEmpty && StubMesh(triangleCount: 3).inspectorFacts.isEmpty)
        #expect(PayloadFact("Triangles", "12") == PayloadFact("Triangles", "12"))
    }
}
