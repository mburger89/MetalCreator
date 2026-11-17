import CreatorGraph
import CreatorPCB
import Foundation

/// KiCad's `kicad_common.json`, which holds the path variables a person defined (`environment.vars`): the newest KiCad version
/// folder that has one (ruling R6). Every path looked at is a dependency of the node, found or not, so installing or editing
/// KiCad's settings runs the node again.
enum KiCadSettingsFiles {
    struct Found {
        var variables = KiCadPathVariables()
        var dependencies: [FileDependency] = []
    }

    static let versions = ["11.0", "10.0", "9.0", "8.0", "7.0", "6.0"]
    static let maxBytes = 4 << 20

    static func read(environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory(),
                     platform: KiCadPlatform = .current) -> Found {
        var found = Found()
        let separator = platform == .windows ? "\\" : "/"
        for version in versions {
            let path = platform.settingsFolder(version: version, environment: environment, home: home)
                + separator + "kicad_common.json"
            guard case .file = ImageResolver.stamp(ofFileAt: path) else {
                found.dependencies.append(FileDependency(stampingFileAt: path))
                continue
            }
            if let file = try? ImageResolver.modelFile(at: path, limit: maxBytes) {
                found.dependencies.append(FileDependency(path: path, stamp: file.stamp))
                found.variables = KiCadPathVariables.parsingCommonSettings(file.data)
            } else {
                found.dependencies.append(FileDependency(stampingFileAt: path))
            }
            break
        }
        return found
    }
}
