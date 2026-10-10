import Foundation
import MetalUI

/// What the packaged `MetalCreator.app` says about itself (docs/superpowers/specs/2026-10-09-packaging-design.md):
/// its name, bundle identifier, version and the `.mcgraph` document type. This is the version's one source:
/// `scripts/package-app.sh` writes the bundle's `Info.plist` with `MetalCreator --info-plist <minimum macOS>`, so the
/// plist is never edited by hand.
public enum AppBundleInfo {
    /// The bundle's name, `CFBundleName`, and the `.app`'s file name.
    public static let name = "MetalCreator"
    /// `CFBundleIdentifier`, in the reverse-DNS domain of the `.mcgraph` type (`ContentType.mcgraph`).
    public static let identifier = "com.metalcreator.MetalCreator"
    /// The executable's name in `Contents/MacOS`, `CFBundleExecutable`.
    public static let executableName = "MetalCreator"
    /// The marketing version, `CFBundleShortVersionString`.
    public static let version = "0.1.0"
    /// The build number, `CFBundleVersion`: raise it for every packaged build that is handed to someone.
    public static let build = "1"
    /// How Finder names a `.mcgraph` file's kind.
    public static let documentTypeName = "MetalCreator Graph"

    /// What `--version` prints, e.g. `MetalCreator 0.1.0 (1)`.
    public static var versionLine: String { "\(name) \(version) (\(build))" }

    /// The bundle's `Info.plist`. `minimumSystemVersion` is `LSMinimumSystemVersion`: the packaging script passes the
    /// newest minimum among the binaries it bundles, which is Package.swift's unless a bundled library needs newer.
    public static func infoPlist(minimumSystemVersion: String) -> [String: Any] {
        let document = ContentType.mcgraph
        return [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDisplayName": name,
            "CFBundleExecutable": executableName,
            "CFBundleIdentifier": identifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
            "CFBundleVersion": build,
            "LSApplicationCategoryType": "public.app-category.graphics-design",
            "LSMinimumSystemVersion": minimumSystemVersion,
            "NSHighResolutionCapable": true,
            "CFBundleDocumentTypes": [
                [
                    "CFBundleTypeName": documentTypeName,
                    "CFBundleTypeRole": "Editor",
                    "LSHandlerRank": "Owner",
                    "LSItemContentTypes": [document.identifier],
                ] as [String: Any],
            ],
            "UTExportedTypeDeclarations": [
                [
                    "UTTypeIdentifier": document.identifier,
                    "UTTypeDescription": documentTypeName,
                    "UTTypeConformsTo": [ContentType.json.identifier],
                    "UTTypeTagSpecification": [
                        "public.filename-extension": [document.preferredFilenameExtension ?? "mcgraph"],
                    ],
                ] as [String: Any],
            ],
        ]
    }

    /// ``infoPlist(minimumSystemVersion:)`` as an XML property list, as `Info.plist` is written.
    public static func infoPlistData(minimumSystemVersion: String) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: infoPlist(minimumSystemVersion: minimumSystemVersion),
                                           format: .xml, options: 0)
    }
}
