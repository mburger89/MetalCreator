import Foundation

/// The platforms KiCad's model folders differ on.
public enum KiCadPlatform: Sendable {
    case macOS, linux, windows

    public static var current: KiCadPlatform {
        #if os(macOS)
        return .macOS
        #elseif os(Windows)
        return .windows
        #else
        return .linux
        #endif
    }

    /// KiCad's library folder of 3D models for major version `n`.
    public func libraryFolder(version n: Int) -> String {
        switch self {
        case .macOS: return "/Applications/KiCad/KiCad.app/Contents/SharedSupport/3dmodels"
        case .linux: return "/usr/share/kicad/3dmodels"
        case .windows: return "C:\\Program Files\\KiCad\\\(n).0\\share\\kicad\\3dmodels"
        }
    }

    /// Where `kicad_common.json` lives for version "n.0".
    public func settingsFolder(version: String, environment: [String: String], home: String) -> String {
        switch self {
        case .macOS:
            return home + "/Library/Preferences/kicad/" + version
        case .linux:
            if let xdg = environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
                return xdg + "/kicad/" + version
            }
            return home + "/.config/kicad/" + version
        case .windows:
            let appData = environment["APPDATA"] ?? (home + "\\AppData\\Roaming")
            return appData + "\\kicad\\" + version
        }
    }
}

/// The path variables a model path may use (`${NAME}`), by name.
public struct KiCadPathVariables: Sendable, Equatable {
    public var values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values
    }

    /// `{"environment": {"vars": {"NAME": "path", …}}}`; `vars` may be null or absent. Anything else unreadable gives none.
    public static func parsingCommonSettings(_ data: Data) -> KiCadPathVariables {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let environment = root["environment"] as? [String: Any],
              let vars = environment["vars"] as? [String: Any] else { return KiCadPathVariables() }
        var values: [String: String] = [:]
        for (name, value) in vars {
            if let text = value as? String { values[name] = text }
        }
        return KiCadPathVariables(values: values)
    }

    /// Ruling R6: the process environment over the settings over the defaults.
    public static func merged(environment: [String: String], settings: KiCadPathVariables,
                              platform: KiCadPlatform) -> KiCadPathVariables {
        var values: [String: String] = [:]
        for version in 6...10 {
            values["KICAD\(version)_3DMODEL_DIR"] = platform.libraryFolder(version: version)
        }
        for (name, value) in settings.values { values[name] = value }
        for (name, value) in environment { values[name] = value }
        return KiCadPathVariables(values: values)
    }
}
