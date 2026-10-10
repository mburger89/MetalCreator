import Foundation
import MetalUI
import Testing
@testable import CreatorApp

/// The packaged app's `Info.plist` (packaging): the version's one source, and the `.mcgraph` type it declares.
struct AppBundleInfoTests {
    @Test func theVersionLineNamesTheMarketingVersionAndTheBuild() {
        #expect(AppBundleInfo.version.wholeMatch(of: /\d+\.\d+\.\d+/) != nil)
        #expect(AppBundleInfo.build.wholeMatch(of: /\d+/) != nil)
        #expect(AppBundleInfo.versionLine == "MetalCreator \(AppBundleInfo.version) (\(AppBundleInfo.build))")
    }

    @Test func thePlistNamesTheBundleItsVersionAndTheMinimumMacOS() throws {
        let plist = try roundTripped(minimumSystemVersion: "27.0")
        #expect(plist["CFBundleExecutable"] as? String == "MetalCreator")
        #expect(plist["CFBundleIdentifier"] as? String == "com.metalcreator.MetalCreator")
        #expect(plist["CFBundleName"] as? String == "MetalCreator")
        #expect(plist["CFBundlePackageType"] as? String == "APPL")
        #expect(plist["CFBundleShortVersionString"] as? String == AppBundleInfo.version)
        #expect(plist["CFBundleVersion"] as? String == AppBundleInfo.build)
        #expect(plist["LSMinimumSystemVersion"] as? String == "27.0")
        #expect(plist["NSHighResolutionCapable"] as? Bool == true)
    }

    /// Finder knows `.mcgraph` files are this app's, under the identifier the file panels already use, so a
    /// double-click or a Dock drop reaches `AppModel.openRequested(_:)` through MetalUI's `App.onOpenURL` (gap M6-d).
    @Test func itOwnsAndExportsTheMcgraphType() throws {
        let plist = try roundTripped(minimumSystemVersion: "26.0")
        let documentTypes = try #require(plist["CFBundleDocumentTypes"] as? [[String: Any]])
        #expect(documentTypes.count == 1)
        #expect(documentTypes.first?["LSItemContentTypes"] as? [String] == [ContentType.mcgraph.identifier])
        #expect(documentTypes.first?["CFBundleTypeRole"] as? String == "Editor")
        #expect(documentTypes.first?["LSHandlerRank"] as? String == "Owner")

        let exported = try #require((plist["UTExportedTypeDeclarations"] as? [[String: Any]])?.first)
        #expect(exported["UTTypeIdentifier"] as? String == ContentType.mcgraph.identifier)
        #expect(exported["UTTypeConformsTo"] as? [String] == [ContentType.json.identifier])
        #expect(ContentType.mcgraph.conformance.contains(ContentType.json.identifier))
        let tags = try #require(exported["UTTypeTagSpecification"] as? [String: Any])
        #expect(tags["public.filename-extension"] as? [String] == ["mcgraph"])
        #expect(ContentType.mcgraph.preferredFilenameExtension == "mcgraph")
    }

    /// MetalUI's probe (`docs/probes/appkit-open-without-document-class.swift`): with MetalUI's application delegate a
    /// document type of exactly this shape needs no `NSDocumentClass`, and the plist declares no URL scheme, so only
    /// files are opened.
    @Test func itNeedsNoDocumentClassAndDeclaresNoURLScheme() throws {
        let plist = try roundTripped(minimumSystemVersion: "26.0")
        let documentType = try #require((plist["CFBundleDocumentTypes"] as? [[String: Any]])?.first)
        #expect(documentType["NSDocumentClass"] == nil)
        #expect(plist["NSPrincipalClass"] == nil)
        #expect(plist["CFBundleURLTypes"] == nil)
    }

    private func roundTripped(minimumSystemVersion: String) throws -> [String: Any] {
        let data = try AppBundleInfo.infoPlistData(minimumSystemVersion: minimumSystemVersion)
        #expect(String(bytes: data, encoding: .utf8)?.hasPrefix("<?xml") == true)
        return try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
