// Test fixture file: three wires straight across the canvas, for the cable tie tests.
import CreatorGeometry
import CreatorGraph
import Foundation
@testable import CreatorEditor

/// Three Number nodes on the left wired across to three on the right, each pair level, so at zoom 1 with no pan each wire's
/// taut route is a straight horizontal line: `upper` from (168, 60) to (600, 60), `lower` from (168, 260) to (600, 260) and
/// `third` from (168, 460) to (600, 460). `upperMiddle`, `lowerMiddle` and `thirdMiddle` are halfway along them, clear of
/// every node. `tie()` holds `upper` and `lower` at (384, 160): its lanes are (384, 158) and (384, 162), and its band runs
/// from (381, 155) to (387, 165).
@MainActor
struct TieScene {
    let a1 = testNode(NumberTestNode.self, id: 1, at: Vector2(0, 0))
    let a2 = testNode(NumberTestNode.self, id: 2, at: Vector2(0, 200))
    let b1 = testNode(NumberTestNode.self, id: 3, at: Vector2(600, 20))
    let b2 = testNode(NumberTestNode.self, id: 4, at: Vector2(600, 220))
    let a3 = testNode(NumberTestNode.self, id: 5, at: Vector2(0, 400))
    let b3 = testNode(NumberTestNode.self, id: 6, at: Vector2(600, 420))
    let upperMiddle = Vector2(384, 60)
    let lowerMiddle = Vector2(384, 260)
    let thirdMiddle = Vector2(384, 460)

    var nodes: [Node] { [a1, a2, b1, b2, a3, b3] }
    var links: [Link] { [wire(a1, "value", b1, "value"), wire(a2, "value", b2, "value"), wire(a3, "value", b3, "value")] }
    var upper: Endpoint { Endpoint(node: b1.id, socket: "value") }
    var lower: Endpoint { Endpoint(node: b2.id, socket: "value") }
    var third: Endpoint { Endpoint(node: b3.id, socket: "value") }

    /// Tie `n` at `position` (stored coordinates), holding `wires` (`upper` and `lower` when not given).
    func tie(_ n: Int = 1, at position: Vector2 = Vector2(384, 160), holding wires: Set<Endpoint>? = nil) -> CableTie {
        CableTie(id: tieID(n), position: position, wires: wires ?? [upper, lower])
    }

    func editor(ties: [CableTie] = [], stickies: [StickyNote] = [], frames: [CommentFrame] = [],
                dock: DockSide = .bottom) -> EditorModel {
        makeEditor(nodes, links, stickies: stickies, frames: frames, ties: ties, dock: dock)
    }
}

/// A tie ID whose sort order is `n`, so tests control the draw order.
func tieID(_ n: Int) -> TieID {
    let digits = String(n)
    let suffix = String(repeating: "0", count: max(0, 12 - digits.count)) + digits
    return TieID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-" + suffix) ?? UUID())
}
