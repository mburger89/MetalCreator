/// Every tool and resource the server offers. Later tasks append their lists here.
@MainActor public enum MCPCatalogue {
    public static var tools: [MCPTool] { ReadTools.tools + EditTools.tools + HistoryTools.tools + FileSettingTools.tools }
    public static var resources: [MCPResource] { ReadTools.resources }
}
