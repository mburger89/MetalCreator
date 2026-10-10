import Foundation
import Testing
@testable import CreatorStyle

/// A colour picker's drag shows each sample at once but writes the theme's file once (`ThemeStore.previewColor` and
/// `saveColors`), where `setColor` writes every call. A failed save puts the saved colours back and says why.
@MainActor
struct ThemeColorPreviewTests {
    let accent = ThemeRole.named("accent")

    /// The accent colour of the custom theme in `folder`'s file, as the next launch would read it.
    func savedAccent(_ folder: ThemeFolder) -> HexColor? {
        folder.load(reserved: []).themes.first?.colors.accent
    }

    @Test func aDragShowsEverySampleButSavesOnlyWhenTold() throws {
        let folder = ThemeFolderTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let store = ThemeStore(folder: folder)
        let copy = try store.duplicate("dracula")
        let role = try #require(accent)
        let before = try #require(savedAccent(folder))
        for step in 1...50 {
            try store.previewColor(HexColor(UInt32(step) << 16), for: role, in: copy.id)
            #expect(store.current.colors.accent == HexColor(UInt32(step) << 16), "shown at once")
        }
        #expect(store.hasUnsavedColors)
        #expect(savedAccent(folder) == before, "50 samples, no write")
        try store.saveColors()
        #expect(!store.hasUnsavedColors)
        #expect(savedAccent(folder) == HexColor(50 << 16), "the last sample, in one write")
        try store.saveColors()   // nothing pending: nothing happens
    }

    @Test func anotherChangeSavesThePreviewedColoursWithIt() throws {
        let folder = ThemeFolderTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let store = ThemeStore(folder: folder)
        let copy = try store.duplicate("dracula")
        let role = try #require(accent)
        try store.previewColor(HexColor(0x123456), for: role, in: copy.id)
        try store.rename(copy.id, to: "Midnight")
        #expect(!store.hasUnsavedColors)
        let saved = try #require(folder.load(reserved: []).themes.first)
        #expect(saved.name == "Midnight" && saved.colors.accent == HexColor(0x123456))
    }

    @Test func previewingAnotherThemeSavesTheFirstOnesColoursFirst() throws {
        let folder = ThemeFolderTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let store = ThemeStore(folder: folder)
        let first = try store.duplicate("dracula")
        let second = try store.duplicate("nord")
        let role = try #require(accent)
        try store.previewColor(HexColor(0x111111), for: role, in: first.id)
        try store.previewColor(HexColor(0x222222), for: role, in: second.id)
        let reloaded = ThemeStore(folder: folder)
        #expect(reloaded.theme(first.id)?.colors.accent == HexColor(0x111111))
        #expect(reloaded.theme(second.id)?.colors.accent != HexColor(0x222222), "the second is still pending")
        try store.saveColors()
        #expect(ThemeStore(folder: folder).theme(second.id)?.colors.accent == HexColor(0x222222))
    }

    @Test func aBuiltInIsRefusedAndNothingIsPending() throws {
        let store = ThemeStore()
        #expect(throws: ThemeProblem.self) { try store.previewColor(HexColor(0), for: try #require(accent), in: "nord") }
        #expect(!store.hasUnsavedColors)
    }

    @Test func aFailedSaveGoesBackToTheSavedColoursAndSaysWhy() throws {
        let folder = ThemeFolderTests.temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder.url) }
        let store = ThemeStore(folder: folder)
        let copy = try store.duplicate("dracula")
        let role = try #require(accent)
        let saved = try #require(savedAccent(folder))
        try store.previewColor(HexColor(0x123456), for: role, in: copy.id)
        // Something that is not a folder in the way of the theme's file makes the write fail.
        try FileManager.default.removeItem(at: folder.url)
        try Data("in the way".utf8).write(to: folder.url)
        #expect(throws: ThemeProblem.self) { try store.saveColors() }
        #expect(store.current.colors.accent == saved && !store.hasUnsavedColors)
        try FileManager.default.removeItem(at: folder.url)
    }

    @Test func deletingAThemeDropsItsPendingColours() throws {
        let store = ThemeStore(folder: ThemeFolderTests.temporaryFolder())
        let copy = try store.duplicate("dracula")
        try store.previewColor(HexColor(0x123456), for: try #require(accent), in: copy.id)
        try store.delete(copy.id)
        #expect(!store.hasUnsavedColors)
        try store.saveColors()
    }
}
