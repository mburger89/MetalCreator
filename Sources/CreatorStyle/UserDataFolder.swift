import Foundation

/// The person's per-user application data folder on this platform: `~/Library/Application Support` on macOS,
/// `$XDG_DATA_HOME` (`~/.local/share` when unset) on Linux and `%APPDATA%` on Windows. Themes and drawing templates live in
/// folders of their own beneath `MetalCreator/`.
public enum UserDataFolder {
    public static var url: URL {
        #if os(macOS)
        URL.applicationSupportDirectory
        #elseif os(Windows)
        if let appData = ProcessInfo.processInfo.environment["APPDATA"] {
            URL(filePath: appData, directoryHint: .isDirectory)
        } else {
            URL.homeDirectory.appending(path: "AppData/Roaming", directoryHint: .isDirectory)
        }
        #else
        if let data = ProcessInfo.processInfo.environment["XDG_DATA_HOME"], data.hasPrefix("/") {
            URL(filePath: data, directoryHint: .isDirectory)
        } else {
            URL.homeDirectory.appending(path: ".local/share", directoryHint: .isDirectory)
        }
        #endif
    }
}
