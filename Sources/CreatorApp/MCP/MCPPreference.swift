import Foundation

/// Whether the person allows AI connections, remembered between launches (spec: off by default). Injected into `MCPService`, so
/// tests never touch the real defaults.
@MainActor
public protocol MCPPreference: AnyObject {
    var allowsAIConnections: Bool { get set }
}

/// A preference that lives as long as the object; what tests use.
@MainActor
public final class MemoryMCPPreference: MCPPreference {
    public var allowsAIConnections: Bool

    public init(allowsAIConnections: Bool = false) {
        self.allowsAIConnections = allowsAIConnections
    }
}

/// The preference in the person's defaults. The app passes `.standard`; tests pass a suite of their own and remove it.
@MainActor
public final class UserDefaultsMCPPreference: MCPPreference {
    public static let key = "MetalCreator.allowsAIConnections"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var allowsAIConnections: Bool {
        get { defaults.bool(forKey: Self.key) }
        set {
            defaults.set(newValue, forKey: Self.key)
            #if !canImport(Darwin)
            defaults.synchronize() // off Apple's platforms the plist is written only here (see `UserDefaultsUnitPreference`)
            #endif
        }
    }
}
