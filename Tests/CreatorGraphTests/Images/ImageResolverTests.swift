import Foundation
import Testing
@testable import CreatorGraph

/// `ImageResolver` (fields spec §5, D11): where a reference's bytes are, whether they changed, and what is refused.
struct ImageResolverTests {
    let folder = TempFolder()
    let png = Data("not really a png, only bytes".utf8)

    func linked(_ file: URL, relative: String? = nil) -> ImageReference {
        .linked(relativePath: relative, absolutePath: file.path(percentEncoded: false))
    }

    // MARK: Embedded

    @Test func anEmbeddedImageIsFoundByItsHashAndReportsWhetherTheDocumentHoldsIt() throws {
        let hash = ImageHash(of: png)
        let held = ImageResolver(embedded: [hash: png])
        #expect(held.stamp(of: .embedded(hash)) == .embedded(hash, isPresent: true))
        #expect(try held.bytes(of: .embedded(hash)) == png)
        let empty = ImageResolver()
        #expect(empty.stamp(of: .embedded(hash)) == .embedded(hash, isPresent: false))
        #expect(throws: ImageProblem.embeddedMissing) { try empty.bytes(of: .embedded(hash)) }
        #expect(empty.location(of: .embedded(hash)) == nil)
    }

    // MARK: Linked files

    @Test func aLinkedFileIsReadAndItsStampChangesWhenItsDateOrSizeDoes() throws {
        let file = try folder.write(png, to: "vent.png")
        try folder.touch(file, Date(timeIntervalSince1970: 1_000_000))
        let resolver = ImageResolver()
        let reference = linked(file)
        let first = resolver.stamp(of: reference)
        let path = file.path(percentEncoded: false)
        #expect(first == .file(path: path, modified: Date(timeIntervalSince1970: 1_000_000), size: png.count))
        #expect(try resolver.bytes(of: reference) == png)
        #expect(resolver.stamp(of: reference) == first, "unchanged")
        try folder.touch(file, Date(timeIntervalSince1970: 2_000_000))
        #expect(resolver.stamp(of: reference) != first, "a new modification date, same bytes")
        try folder.touch(file, Date(timeIntervalSince1970: 1_000_000))
        try Data("longer than before, by far".utf8).write(to: file)
        try folder.touch(file, Date(timeIntervalSince1970: 1_000_000))
        #expect(resolver.stamp(of: reference) != first, "the same date, another size")
    }

    @Test func theRelativePathIsTriedFirstThenTheAbsoluteOne() throws {
        let beside = try folder.write(Data("beside".utf8), to: "doc/maps/vent.png")
        let elsewhere = try folder.write(Data("elsewhere!".utf8), to: "other/vent.png")
        let reference = ImageReference.linked(relativePath: "maps/vent.png", absolutePath: elsewhere.path(percentEncoded: false))
        let docFolder = folder.url.appending(path: "doc", directoryHint: .isDirectory)
        #expect(try ImageResolver(documentFolder: docFolder).bytes(of: reference) == Data("beside".utf8))
        #expect(try ImageResolver().bytes(of: reference) == Data("elsewhere!".utf8), "an unsaved document has no folder")
        try FileManager.default.removeItem(at: beside)
        #expect(try ImageResolver(documentFolder: docFolder).bytes(of: reference) == Data("elsewhere!".utf8), "the fallback")
    }

    @Test func aMissingFileSaysWhereItLookedAndLeavesWorkToTheInspector() throws {
        let gone = folder.url.appending(path: "textures/vent-mask.png")
        let reference = linked(gone)
        let resolver = ImageResolver()
        #expect(resolver.stamp(of: reference) == .missing(path: gone.path(percentEncoded: false)))
        let textures = folder.url.appending(path: "textures", directoryHint: .isDirectory)
        let folderPath = textures.standardizedFileURL.path(percentEncoded: false)
        #expect(throws: ImageProblem.notFound(name: "vent-mask.png", folder: folderPath)) { try resolver.bytes(of: reference) }
        let message = ImageProblem.notFound(name: "vent-mask.png", folder: folderPath).message
        #expect(message.hasSuffix("textures/. Relink it in the inspector."))
    }

    @Test func aFolderOrADeviceIsNotAFileAndIsNeverOpened() throws {
        try folder.write(png, to: "maps/inside.png")
        for path in [folder.url.appending(path: "maps").path(percentEncoded: false), "/dev/zero", "/dev/null"] {
            let reference = ImageReference.linked(relativePath: nil, absolutePath: path)
            let standard = URL(filePath: path).standardizedFileURL.path(percentEncoded: false)
            #expect(ImageResolver().stamp(of: reference) == .notAFile(path: standard))
            #expect(throws: ImageProblem.notAFile(name: reference.fileName ?? "")) { try ImageResolver().bytes(of: reference) }
        }
    }

    /// The stamp saw a file, then the path became a named pipe: `read` opens without blocking and checks what it opened, so it
    /// answers at once instead of waiting for a writer that never comes. (A regular file and a pipe cannot be told apart by a
    /// test that goes through `bytes(of:)`, which checks the path first; this one calls the reader itself.)
    @Test(.timeLimit(.minutes(1))) func aPathSwappedForANamedPipeAfterTheCheckIsRefusedNotWaitedOn() throws {
        let pipe = folder.url.appending(path: "swapped.png")
        #expect(mkfifo(pipe.path(percentEncoded: false), 0o644) == 0)
        #expect(throws: ImageProblem.notAFile(name: "swapped.png")) { try ImageResolver.read(pipe, name: "swapped.png") }
        let real = try folder.write(png, to: "real.png")
        #expect(try ImageResolver.read(real, name: "real.png") == png)
        #expect(throws: ImageProblem.self) { try ImageResolver.read(folder.url.appending(path: "none.png"), name: "none.png") }
    }

    @Test func aSymbolicLinkToAFileIsFollowed() throws {
        let target = try folder.write(png, to: "real.png")
        let link = folder.url.appending(path: "link.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(try ImageResolver().bytes(of: linked(link)) == png)
    }

    @Test func aRelativePathIsAppliedFromTheSymlinkResolvedDocumentFolder() throws {
        try folder.write(Data("beside".utf8), to: "real/project/shared/vent.png")
        try folder.write(Data("elsewhere!".utf8), to: "fallback/vent.png")
        try FileManager.default.createDirectory(at: folder.url.appending(path: "real/project/doc"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder.url.appending(path: "other"), withIntermediateDirectories: true)
        let linkedFolder = folder.url.appending(path: "other/doc", directoryHint: .isDirectory)
        try FileManager.default.createSymbolicLink(at: linkedFolder, withDestinationURL: folder.url.appending(path: "real/project/doc"))
        // Lexically `other/doc/../shared` is `other/shared`, which does not exist; through the link it is `real/project/shared`.
        let fallback = folder.url.appending(path: "fallback/vent.png")
        let reference = ImageReference.linked(relativePath: "../shared/vent.png", absolutePath: fallback.path(percentEncoded: false))
        let resolver = ImageResolver(documentFolder: linkedFolder)
        #expect(try resolver.bytes(of: reference) == Data("beside".utf8))
        let found = try #require(resolver.location(of: reference))
        #expect(found.resolvingSymlinksInPath().path(percentEncoded: false)
            == folder.url.appending(path: "real/project/shared/vent.png").resolvingSymlinksInPath().path(percentEncoded: false))
        // And what saving writes from that folder reads back to the same file.
        let stored = resolver.stored(reference, inDocumentFolder: linkedFolder)
        guard case .linked(let relative?, _) = stored else { Issue.record("expected a linked reference"); return }
        #expect(relative == "../shared/vent.png")
    }

    @Test func aFileOverSixteenMegabytesIsRefusedUnreadAndOneAtTheLimitIsRead() throws {
        let big = try folder.write(Data(count: ImageLimits.maxBytes), to: "exact.png")
        #expect(try ImageResolver().bytes(of: linked(big)).count == ImageLimits.maxBytes)
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(ImageLimits.maxBytes + 1))
        try handle.close()
        #expect(throws: ImageProblem.tooManyBytes(ImageLimits.maxBytes + 1)) { try ImageResolver().bytes(of: linked(big)) }
    }

    @Test func bytesOfAChosenFileAreBoundedLikeAnyOther() throws {
        let file = try folder.write(png, to: "a.png")
        #expect(try ImageResolver.bytes(ofFileAt: file) == png)
        #expect(throws: ImageProblem.self) { try ImageResolver.bytes(ofFileAt: folder.url.appending(path: "nope.png")) }
        #expect(throws: ImageProblem.self) { try ImageResolver.bytes(ofFileAt: folder.url) }
    }

    @Test func readingAndStampingWriteNothingBesideTheImage() throws {
        let file = try folder.write(png, to: "maps/vent.png")
        let before = folder.listing
        let resolver = ImageResolver(documentFolder: folder.url)
        _ = resolver.stamp(of: linked(file))
        _ = try resolver.bytes(of: linked(file))
        _ = resolver.stored(linked(file), inDocumentFolder: folder.url)
        #expect(folder.listing == before)
    }

    // MARK: Relative paths and saving

    @Test func relativePathsGoDownUpAndAcross() {
        let root = URL(filePath: "/work/project", directoryHint: .isDirectory)
        func relative(_ folder: String, _ file: String) -> String {
            ImageResolver.relativePath(from: root.appending(path: folder, directoryHint: .isDirectory), to: root.appending(path: file))
        }
        #expect(relative("doc", "doc/vent.png") == "vent.png")
        #expect(relative("doc", "doc/maps/vent.png") == "maps/vent.png")
        #expect(relative("doc", "vent.png") == "../vent.png")
        #expect(relative("doc/deep", "shared/vent.png") == "../../shared/vent.png")
        #expect(relative("doc", "docs/vent.png") == "../docs/vent.png", "a shared name prefix is not a shared folder")
    }

    @Test func savingWritesBothPathsOfAFoundFileAndKeepsAMissingOnesAsTheyWere() throws {
        let file = try folder.write(png, to: "doc/maps/vent.png")
        let docFolder = folder.url.appending(path: "doc", directoryHint: .isDirectory)
        let resolver = ImageResolver()
        let unsaved = linked(file)
        let stored = resolver.stored(unsaved, inDocumentFolder: docFolder)
        #expect(stored == .linked(relativePath: "maps/vent.png", absolutePath: file.standardizedFileURL.path(percentEncoded: false)))
        let moved = resolver.stored(stored, inDocumentFolder: folder.url.appending(path: "elsewhere", directoryHint: .isDirectory))
        #expect(moved == .linked(relativePath: "../doc/maps/vent.png", absolutePath: file.standardizedFileURL.path(percentEncoded: false)),
                "Save As elsewhere: the relative path is made again from the new folder")
        let missing = ImageReference.linked(relativePath: "gone/x.png", absolutePath: "/no/such/x.png")
        #expect(resolver.stored(missing, inDocumentFolder: docFolder) == missing)
        let hash = ImageHash(of: png)
        #expect(resolver.stored(.embedded(hash), inDocumentFolder: docFolder) == .embedded(hash))
        let absolute = file.standardizedFileURL.path(percentEncoded: false)
        #expect(resolver.stored(unsaved, inDocumentFolder: nil) == .linked(relativePath: nil, absolutePath: absolute))
    }
}
