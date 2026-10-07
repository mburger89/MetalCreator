import CreatorKernel

extension KernelError {
    /// Wraps a shim failure for `operation` in plain language.
    static func occt(_ operation: String, _ error: OCCTError) -> KernelError {
        .operationFailed(operation: operation, reason: plainReason(error.message))
    }

    /// OCCT's own messages are terse ("BRep_API: command not done"); make them readable.
    static func plainReason(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("not done") || lower.contains("notdone") || lower.contains("unknown occt") {
            return "the geometry could not be built with these inputs."
        }
        return message.hasSuffix(".") ? message : message + "."
    }
}
