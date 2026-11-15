import Foundation

/// JSON-RPC 2.0 framing: the error codes and the response builders. Every line ends in "\n".
enum JSONRPC {
    static let parseError = -32700
    static let invalidRequest = -32600
    static let methodNotFound = -32601
    static let invalidParams = -32602
    /// The app already serves another client (the listener's refusal; the bridge reads it).
    static let alreadyConnected = -32001

    static func line(_ value: JSONValue) -> Data {
        var data = value.encoded()
        data.append(0x0A)
        return data
    }

    static func result(id: JSONValue, _ result: JSONValue) -> Data {
        line(.object(["jsonrpc": .string("2.0"), "id": id, "result": result]))
    }

    static func error(id: JSONValue, code: Int, _ message: String) -> Data {
        line(.object([
            "jsonrpc": .string("2.0"), "id": id,
            "error": .object(["code": .int(code), "message": .string(message)]),
        ]))
    }

    static func notification(_ method: String, _ params: JSONValue) -> Data {
        line(.object(["jsonrpc": .string("2.0"), "method": .string(method), "params": params]))
    }
}
