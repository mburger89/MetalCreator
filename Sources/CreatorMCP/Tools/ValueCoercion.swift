import CreatorGeometry
import CreatorGraph
import CreatorKernel
import Foundation

/// Turns a client's JSON into the `ConstantValue` an input stores, or says in a sentence why it can't.
public enum ValueCoercion {
    /// The label the inspector shows for a socket ("Distance", "Start angle").
    public static func label(for socket: SocketName) -> String {
        var words: [String] = []
        var current = ""
        for character in socket.rawValue {
            if character.isUppercase, !current.isEmpty {
                words.append(current)
                current = ""
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        let sentence = words.map { $0.lowercased() }.joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    /// `nil` in the success case clears the input. `options` are a segmented control's names, in index order.
    public static func value(_ json: JSONValue, for spec: SocketSpec, options: [String]?) -> Result<ConstantValue?, Refusal> {
        if json == .null { return .success(nil) }
        let label = label(for: spec.name)
        switch spec.type {
        case .number: return number(json, label: label, range: spec.range)
        case .integer: return integer(json, label: label, options: options)
        case .bool:
            guard let flag = json.bool else { return .failure(Refusal("\(label) needs true or false.")) }
            return .success(.bool(flag))
        case .vector:
            guard let items = json.array, items.count == 3, let x = items[0].double, let y = items[1].double, let z = items[2].double,
                  [x, y, z].allSatisfy(\.isFinite) else {
                return .failure(Refusal("\(label) needs three numbers, like [0, 0, 10]."))
            }
            return .success(.vector(Vector3(x, y, z)))
        default:
            return .failure(Refusal("\(label) can't be set to a value; wire a node into it."))
        }
    }

    /// A text setting (a Path Mapper's rule, a Cull Index's indices).
    public static func text(_ json: JSONValue, label: String) -> Result<ConstantValue?, Refusal> {
        if json == .null { return .success(nil) }
        guard let text = json.string else { return .failure(Refusal("\(label) needs text.")) }
        return .success(.text(text))
    }

    private static func number(_ json: JSONValue, label: String, range: ClosedRange<Double>?) -> Result<ConstantValue?, Refusal> {
        guard let value = json.double, value.isFinite else { return .failure(Refusal("\(label) needs a number.")) }
        if let range, !range.contains(value) {
            let low = ValueSummary.format(range.lowerBound)
            let high = ValueSummary.format(range.upperBound)
            return .failure(Refusal("\(label) must be between \(low) and \(high)."))
        }
        return .success(.number(value))
    }

    private static func integer(_ json: JSONValue, label: String, options: [String]?) -> Result<ConstantValue?, Refusal> {
        guard let options, !options.isEmpty else {
            guard let value = json.int else { return .failure(Refusal("\(label) needs a whole number.")) }
            return .success(.integer(value))
        }
        let choices = options.joined(separator: ", ")
        if let name = json.string {
            guard let index = options.firstIndex(where: { $0.lowercased() == name.lowercased() }) else {
                return .failure(Refusal("\(label) must be one of \(choices)."))
            }
            return .success(.integer(index))
        }
        guard let index = json.int, options.indices.contains(index) else {
            return .failure(Refusal("\(label) must be one of \(choices), or an index from 0 to \(options.count - 1)."))
        }
        return .success(.integer(index))
    }
}
