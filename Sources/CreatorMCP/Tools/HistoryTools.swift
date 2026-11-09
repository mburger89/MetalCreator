/// Undo and redo of the client's own steps.
@MainActor public enum HistoryTools {
    public static var tools: [MCPTool] {
        [
            MCPTool(
                name: "undo", description: "Takes back the last step you made, if no one else has made a step since.",
                inputSchema: .object(["type": .string("object"), "properties": .object([:])])
            ) { _, session, _ in
                await EditOutcome.observe(session: session) { session.undoClientStep() }
            },
            MCPTool(
                name: "redo", description: "Re-applies the step you took back, if no one else has changed the document since.",
                inputSchema: .object(["type": .string("object"), "properties": .object([:])])
            ) { _, session, _ in
                await EditOutcome.observe(session: session) { session.redoClientStep() }
            },
        ]
    }
}
