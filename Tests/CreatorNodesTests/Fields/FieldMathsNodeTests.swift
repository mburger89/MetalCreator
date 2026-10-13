import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Testing
@testable import CreatorNodes

/// Add, Multiply, Min / Max, Remap, Clamp and Smooth Blend (fields spec §3.2), against hand-worked values.
struct FieldMathsNodeTests {
    /// A field of the x coordinate: a Linear Gradient along +X of length 1.
    func xField(_ h: inout Harness) -> Node {
        let plane = h.add(PlaneNode.self, ["orientation": .integer(2)])  // YZ: its normal is +X
        let gradient = h.add(LinearGradientNode.self, ["length": .number(1)])
        h.wire(plane, "plane", to: gradient, "plane")
        return gradient
    }

    let line = [Vector3(-10, 0, 0), Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(20, 0, 0), Vector3(30, 0, 0)]

    // MARK: Add and Multiply

    @Test func addAddsTwoFieldsAndTwoTypedNumbersAreConstantFields() async throws {
        var h = Harness()
        let add = h.add(FieldAddNode.self, ["a": .number(2), "b": .number(3)])
        let report = try await h.run([add])
        #expect(report.field(add)?.description == "2 + 3")
        #expect(try await sampled(report.field(add), at: [.zero, Vector3(9, 9, 9)]) == [5, 5])
    }

    @Test func multiplyByPointFiveTypedIntoB() async throws {
        var h = Harness()
        let x = xField(&h)
        let multiply = h.add(FieldMultiplyNode.self, ["b": .number(0.5)])
        h.wire(x, "field", to: multiply, "a")
        let report = try await h.run([multiply])
        #expect(report.field(multiply)?.description == "linear(length 1) × 0.5")
        #expect(try await sampled(report.field(multiply), at: line) == [-5, 0, 5, 10, 15])
    }

    @Test func theDefaultsAreTheIdentities() async throws {
        var h = Harness()
        let add = h.add(FieldAddNode.self), multiply = h.add(FieldMultiplyNode.self)
        let report = try await h.run([add, multiply])
        #expect(try await sampled(report.field(add), at: [.zero]) == [0])
        #expect(try await sampled(report.field(multiply), at: [.zero]) == [1])
    }

    @Test func aNumberOrIntegerNodeWiresStraightIntoAField() async throws {
        var h = Harness()
        let number = h.add(NumberNode.self, ["value": .number(4.5)]), whole = h.add(IntegerNode.self, ["value": .integer(2)])
        let add = h.add(FieldAddNode.self)
        h.wire(number, "value", to: add, "a")
        h.wire(whole, "value", to: add, "b")
        let report = try await h.run([add])
        #expect(report.field(add)?.description == "4.5 + 2")
    }

    @Test func aListOfNumbersBroadcastsIntoAListOfFields() async throws {
        var h = Harness()
        let series = h.add(SeriesNode.self, ["count": .integer(3)])
        let add = h.add(FieldAddNode.self, ["b": .number(10)])
        h.wire(series, "values", to: add, "a")
        let report = try await h.run([add])
        #expect(report.fields(add).map(\.description) == ["0 + 10", "1 + 10", "2 + 10"])
    }

    @Test func addingAnAdditionInsideAMultiplyIsBracketed() async throws {
        var h = Harness()
        let add = h.add(FieldAddNode.self, ["a": .number(1), "b": .number(2)])
        let multiply = h.add(FieldMultiplyNode.self, ["b": .number(3)])
        h.wire(add, "field", to: multiply, "a")
        let report = try await h.run([multiply])
        #expect(report.field(multiply)?.description == "(1 + 2) × 3")
        #expect(try await sampled(report.field(multiply), at: [.zero]) == [9])
    }

    // MARK: Min / Max

    @Test func minAndMaxPickTheLowerOrHigherField() async throws {
        var h = Harness()
        let x = xField(&h)
        let low = h.add(FieldMinMaxNode.self, ["mode": .integer(0), "b": .number(5)])
        let high = h.add(FieldMinMaxNode.self, ["mode": .integer(1), "b": .number(5)])
        h.wire(x, "field", to: low, "a")
        h.wire(x, "field", to: high, "a")
        let report = try await h.run([low, high])
        #expect(report.field(low)?.description == "min(linear(length 1), 5)")
        #expect(report.field(high)?.description == "max(linear(length 1), 5)")
        #expect(try await sampled(report.field(low), at: line) == [-10, 0, 5, 5, 5])
        #expect(try await sampled(report.field(high), at: line) == [5, 5, 10, 20, 30])
    }

    @Test func anOutOfRangeModeIsRefused() async throws {
        var h = Harness()
        let node = h.add(FieldMinMaxNode.self, ["mode": .integer(4)])
        let report = try await h.run([node])
        #expect(report.error(node) == "Choose Min or Max for “mode”.")
    }

    // MARK: Remap

    @Test func remapMapsAndClampsLikeTheSpecsExample() async throws {
        var h = Harness()
        let x = xField(&h)
        let remap = h.add(FieldRemapNode.self, [
            "fromLow": .number(0), "fromHigh": .number(20), "toLow": .number(1), "toHigh": .number(0),
        ])
        h.wire(x, "field", to: remap, "field")
        let report = try await h.run([remap])
        #expect(report.field(remap)?.description == "remap(linear(length 1), 0…20 → 1…0)")
        #expect(try await sampled(report.field(remap), at: line) == [1, 1, 0.5, 0, 0])
    }

    @Test func switchingClampOffLetsTheMapRunOn() async throws {
        var h = Harness()
        let x = xField(&h)
        let remap = h.add(FieldRemapNode.self, [
            "fromLow": .number(0), "fromHigh": .number(20), "toLow": .number(1), "toHigh": .number(0), "clamp": .bool(false),
        ])
        h.wire(x, "field", to: remap, "field")
        let report = try await h.run([remap])
        #expect(report.field(remap)?.description == "remap(linear(length 1), 0…20 → 1…0, unclamped)")
        #expect(try await sampled(report.field(remap), at: line) == [1.5, 1, 0.5, 0, -0.5])
    }

    @Test func clampStartsOn() {
        #expect(FieldRemapNode.inputs.first { $0.name == "clamp" }?.defaultValue == .bool(true))
        #expect(BuiltInNodes.registry.makeNode(FieldRemapNode.typeID).inputValues["clamp"] == nil, "a socket default, not a stored setting")
    }

    @Test func anEmptyFromRangeIsRefusedWithItsNumber() async throws {
        var h = Harness()
        let remap = h.add(FieldRemapNode.self, ["fromLow": .number(3), "fromHigh": .number(3)])
        let report = try await h.run([remap])
        #expect(report.error(remap) == "Remap's from range is empty (both ends are 3).")
    }

    @Test func anEmptyToRangeIsFineAndAFromRangeBackwardsIsFine() async throws {
        var h = Harness()
        let x = xField(&h)
        let flat = h.add(FieldRemapNode.self, [
            "fromLow": .number(0), "fromHigh": .number(20), "toLow": .number(2), "toHigh": .number(2),
        ])
        let backwards = h.add(FieldRemapNode.self, [
            "fromLow": .number(20), "fromHigh": .number(0), "toLow": .number(0), "toHigh": .number(1),
        ])
        h.wire(x, "field", to: flat, "field")
        h.wire(x, "field", to: backwards, "field")
        let report = try await h.run([flat, backwards])
        #expect(try await sampled(report.field(flat), at: line) == [2, 2, 2, 2, 2])
        #expect(try await sampled(report.field(backwards), at: line) == [1, 1, 0.5, 0, 0])
    }

    @Test func remapRefusesRangeEndsThatAreNotFiniteNumbers() async throws {
        // A wired infinity can't be typed (the editor refuses it), so the node is called directly.
        let node = BuiltInNodes.registry.makeNode(FieldRemapNode.typeID)
        let inputs = NodeInputs(item: 0, slots: [
            "field": .item(.field(.constant(0))), "fromLow": .item(.number(0)), "fromHigh": .item(.number(.infinity)),
            "toLow": .item(.number(0)), "toHigh": .item(.number(1)), "clamp": .item(.bool(true)),
        ])
        await #expect(throws: NodeError.invalidValue("Remap's ranges must be finite numbers.")) {
            _ = try await FieldRemapNode.evaluate(inputs, kernel: FakeKernel(), context: EvalContext(node: node, item: 0, parameters: [:]))
        }
    }

    // MARK: Clamp

    @Test func clampHoldsAFieldBetweenItsLimits() async throws {
        var h = Harness()
        let x = xField(&h)
        let clamp = h.add(FieldClampNode.self, ["low": .number(0), "high": .number(15)])
        h.wire(x, "field", to: clamp, "field")
        let report = try await h.run([clamp])
        #expect(report.field(clamp)?.description == "clamp(linear(length 1), 0…15)")
        #expect(try await sampled(report.field(clamp), at: line) == [0, 0, 10, 15, 15])
    }

    @Test func clampWithTheLimitsTheWrongWayRoundFailsAndEqualLimitsDoNot() async throws {
        var h = Harness()
        let wrong = h.add(FieldClampNode.self, ["low": .number(3), "high": .number(1)])
        let equal = h.add(FieldClampNode.self, ["low": .number(2), "high": .number(2)])
        let report = try await h.run([wrong, equal])
        #expect(report.error(wrong) == "Clamp's low end (3) is above its high end (1).")
        #expect(report.isOK(equal))
    }

    // MARK: Smooth Blend

    @Test func smoothBlendDipsBelowTheMinimumWithinItsWidthAndMatchesItBeyond() async throws {
        var h = Harness()
        let blend = h.add(FieldSmoothBlendNode.self, ["a": .number(0), "b": .number(1), "width": .number(2)])
        let far = h.add(FieldSmoothBlendNode.self, ["a": .number(0), "b": .number(5), "width": .number(2)])
        let plain = h.add(FieldSmoothBlendNode.self, ["a": .number(3), "b": .number(1), "width": .number(0)])
        let report = try await h.run([blend, far, plain])
        #expect(report.field(blend)?.description == "smoothMin(0, 1, width 2)")
        #expect(try await sampled(report.field(blend), at: [.zero]) == [-0.125])
        #expect(try await sampled(report.field(far), at: [.zero]) == [0])
        #expect(try await sampled(report.field(plain), at: [.zero]) == [1], "width 0 is the plain minimum")
    }

    @Test func aNegativeWidthIsRefused() async throws {
        var h = Harness()
        let blend = h.add(FieldSmoothBlendNode.self, ["width": .number(-1)])
        let report = try await h.run([blend])
        #expect(report.error(blend) == "“width” must be 0 or more.")
    }

    // MARK: types (D4)

    @Test func aFieldCannotBeWiredIntoANumberSocketButANumberCanBeWiredIntoAFieldOne() {
        var h = Harness()
        let radial = h.add(RadialGradientNode.self)
        let circle = h.add(CircleNode.self)
        let number = h.add(NumberNode.self)
        let add = h.add(FieldAddNode.self)
        let registry = BuiltInNodes.registry
        let toNumber = h.graph.connectionProblem(from: Endpoint(node: radial.id, socket: "field"),
                                                 to: Endpoint(node: circle.id, socket: "diameter"), registry: registry)
        #expect(toNumber == .typeMismatch(from: .field, to: .number))
        let toField = h.graph.connectionProblem(from: Endpoint(node: number.id, socket: "value"),
                                                to: Endpoint(node: add.id, socket: "a"), registry: registry)
        #expect(toField == nil)
        let fieldToField = h.graph.connectionProblem(from: Endpoint(node: radial.id, socket: "field"),
                                                     to: Endpoint(node: add.id, socket: "b"), registry: registry)
        #expect(fieldToField == nil)
    }

    @Test func aCombinedFieldKeepsTheSourcesItWasBuiltFrom() async throws {
        var h = Harness()
        let noise = h.add(NoiseFieldNode.self, ["seed": .integer(4)])
        let remap = h.add(FieldRemapNode.self, [
            "fromLow": .number(0), "fromHigh": .number(1), "toLow": .number(10), "toHigh": .number(20),
        ])
        let multiply = h.add(FieldMultiplyNode.self, ["b": .number(2)])
        h.wire(noise, "field", to: remap, "field")
        h.wire(remap, "field", to: multiply, "a")
        let report = try await h.run([multiply])
        #expect(report.field(multiply)?.description == "remap(noise(seed 4, scale 10, octaves 1), 0…1 → 10…20) × 2")
        let values = try await sampled(report.field(multiply), at: (0..<50).map { Vector3(Double($0) * 0.9, 1, 2) })
        #expect(values.allSatisfy { (20.0...40.0).contains($0) })
    }
}
