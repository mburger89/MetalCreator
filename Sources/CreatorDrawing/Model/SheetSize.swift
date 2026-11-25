import CreatorGeometry

/// A paper size (plan R14): ISO 5457 A4 to A0 and ANSI A to E.
public enum SheetSize: String, Sendable, Codable, CaseIterable {
    case a4, a3, a2, a1, a0, ansiA, ansiB, ansiC, ansiD, ansiE

    /// Width by height in millimetres when held upright.
    public var portrait: Vector2 {
        switch self {
        case .a4: Vector2(210, 297)
        case .a3: Vector2(297, 420)
        case .a2: Vector2(420, 594)
        case .a1: Vector2(594, 841)
        case .a0: Vector2(841, 1189)
        case .ansiA: Vector2(215.9, 279.4)
        case .ansiB: Vector2(279.4, 431.8)
        case .ansiC: Vector2(431.8, 558.8)
        case .ansiD: Vector2(558.8, 863.6)
        case .ansiE: Vector2(863.6, 1117.6)
        }
    }

    /// "A3", "B".
    public var title: String {
        switch self {
        case .a4: "A4"
        case .a3: "A3"
        case .a2: "A2"
        case .a1: "A1"
        case .a0: "A0"
        case .ansiA: "A"
        case .ansiB: "B"
        case .ansiC: "C"
        case .ansiD: "D"
        case .ansiE: "E"
        }
    }

    /// A0 to A2 and ANSI C to E take the 3.5 mm lettering.
    public var isLarge: Bool {
        switch self {
        case .a0, .a1, .a2, .ansiC, .ansiD, .ansiE: true
        case .a4, .a3, .ansiA, .ansiB: false
        }
    }
}

public enum SheetOrientation: String, Sendable, Codable {
    case landscape
    case portrait
}
