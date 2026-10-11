import CreatorGeometry
import Testing
@testable import CreatorNodes

/// Which holes share a tool: one build per distinct size (patterns spec §7).
struct ToolPlanTests {
    func size(_ diameter: Double, depth: Double = 6, style: HoleStyle = .plain) -> HoleSize {
        HoleSize(diameter: diameter, depth: depth, style: style, counterbore: (9, 2), countersink: (10, .degrees(90)))
    }

    @Test func holesOfOneSizeShareOneTool() {
        let plan = ToolPlan(sizes: (0..<24).map { size($0 % 2 == 0 ? 5 : 6) })
        #expect(plan.distinct.count == 2)
        #expect(plan.toolIndex == (0..<24).map { $0 % 2 })
    }

    @Test func aSettingThatThePlainStyleIgnoresDoesNotMakeANewTool() {
        let a = HoleSize(diameter: 5, depth: 6, style: .plain, counterbore: (9, 2), countersink: (10, .degrees(90)))
        let b = HoleSize(diameter: 5, depth: 6, style: .plain, counterbore: (12, 1), countersink: (8, .degrees(60)))
        #expect(a == b)
        #expect(ToolPlan(sizes: [a, b]).distinct.count == 1)
    }

    @Test func aStyleThatUsesASettingKeepsItApart() {
        let a = HoleSize(diameter: 5, depth: 6, style: .counterbore, counterbore: (9, 2), countersink: (10, .degrees(90)))
        let b = HoleSize(diameter: 5, depth: 6, style: .counterbore, counterbore: (12, 2), countersink: (10, .degrees(90)))
        #expect(a != b)
    }
}
