import CreatorGeometry
import CreatorGraph

extension ReadTools {
    /// An integral number as `.int`, so `3` doesn't print as `3.0`.
    static func number(_ value: Double) -> JSONValue {
        guard value.isFinite else { return .null }
        return value == value.rounded() && abs(value) < 1e15 ? .int(Int(value)) : .number(value)
    }

    static func constantJSON(_ value: ConstantValue) -> JSONValue {
        switch value {
        case .number(let number): Self.number(number)
        case .integer(let integer): .int(integer)
        case .bool(let flag): .bool(flag)
        case .vector(let vector): vectorJSON(vector)
        case .plane(let plane): planeJSON(plane)
        case .text(let text): .string(text)
        case .edgePicks(let picks): .string(picks.count == 1 ? "1 edge pick" : "\(picks.count) edge picks")
        case .sketch: .string("sketch")
        case .facePick: .string("face pick")
        case .image(let reference), .meshFile(let reference): fileStatus(reference)
        }
    }

    static func vectorJSON(_ vector: Vector3) -> JSONValue {
        .array([number(vector.x), number(vector.y), number(vector.z)])
    }

    private static func planeJSON(_ plane: Plane) -> JSONValue {
        .object(["origin": vectorJSON(plane.origin), "normal": vectorJSON(plane.normal), "x_axis": vectorJSON(plane.xAxis)])
    }

    private static func fileStatus(_ reference: ImageReference) -> JSONValue {
        switch reference {
        case .embedded: .object(["kind": .string("embedded")])
        case .linked(_, let path): .object(["kind": .string("linked"), "path": .string(path)])
        }
    }
}
