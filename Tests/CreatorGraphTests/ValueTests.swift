import Foundation
import Testing
@testable import CreatorGeometry
@testable import CreatorGraph

struct ValueTests {
    @Test func integerWidensToNumberButNotTheReverse() {
        #expect(SocketType.number.accepts(.integer))
        #expect(!SocketType.integer.accepts(.number))
        #expect(SocketType.plane.accepts(.vector))
        #expect(!SocketType.solid.accepts(.profile))
    }

    @Test func convertsIntegerScalarToNumber() throws {
        let converted = try #require(Scalar.integer(4).converted(to: .number))
        guard case .number(let value) = converted else { Issue.record("expected number"); return }
        #expect(value == 4)
    }

    @Test func vectorConvertsToPlaneThroughThatPoint() throws {
        let converted = try #require(Scalar.vector(Vector3(1, 2, 3)).converted(to: .plane))
        guard case .plane(let plane) = converted else { Issue.record("expected plane"); return }
        #expect(plane.origin == Vector3(1, 2, 3))
        #expect(plane.normal == .unitZ)
    }

    @Test func convertingADepthOneTreeGivesAList() throws {
        let converted = try #require(Value.tree(.list([.integer(1), .integer(2)])).converted(to: .number))
        guard case .list(let scalars) = converted else { Issue.record("expected list"); return }
        #expect(scalars.count == 2)
    }

    @Test func impossibleConversionIsNil() {
        #expect(Scalar.bool(true).converted(to: .number) == nil)
    }

    @Test func listConversionFailsIfAnyItemFails() {
        #expect(Value.list([.integer(1), .bool(true)]).converted(to: .number) == nil)
    }

    @Test(arguments: [
        ConstantValue.number(6.5), .integer(4), .bool(true), .vector(Vector3(1, 2, 3)), .plane(.xz), .text("hello"),
    ])
    func constantsRoundTripThroughJSON(_ value: ConstantValue) throws {
        let data = try JSONEncoder().encode(value)
        #expect(try JSONDecoder().decode(ConstantValue.self, from: data) == value)
    }

    @Test func constantJSONIsReadable() throws {
        let json = try #require(String(bytes: try JSONEncoder().encode(ConstantValue.number(6)), encoding: .utf8))
        #expect(json.contains("\"type\":\"number\""))
    }

    @Test func socketNameKeyedDictionariesEncodeAsObjects() throws {
        let data = try JSONEncoder().encode([SocketName("width"): ConstantValue.number(60)])
        let json = try #require(String(bytes: data, encoding: .utf8))
        #expect(json.hasPrefix("{\"width\""))
    }

    @Test func nonFiniteConstantsAreFlagged() {
        #expect(!ConstantValue.number(.nan).isFinite)
        #expect(!ConstantValue.vector(Vector3(0, .infinity, 0)).isFinite)
        #expect(ConstantValue.integer(3).isFinite)
    }
}
