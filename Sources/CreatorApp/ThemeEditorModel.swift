import CreatorStyle
import Foundation
import MetalUI
import Observation

/// The theme editor's state and behaviour (Themes milestone). It edits the theme the window shows, so every change
/// is seen at once on the panels and in the viewport; choosing another theme in it shows that one everywhere. All
/// changes go through `ThemeStore`, which saves them; the views only forward. A problem is shown as one sentence
/// (`message`) until the next action.
@MainActor
@Observable
public final class ThemeEditorModel {
    public let themes: ThemeStore
    public private(set) var isOpen = false
    /// The last action's problem, or the themes folder's load problems when the editor opens.
    public private(set) var message: String?
    /// The theme Delete… asked about, while its confirmation is up. The confirmation deletes this one even if
    /// another theme is shown by now (View ▸ Theme stays reachable while the dialog is up).
    public private(set) var pendingDeleteID: ColorTheme.ID?
    /// The name typed into the name field and not yet committed, with the theme it was typed for.
    private var nameDraft: (id: ColorTheme.ID, text: String)?
    /// The window's open and save panels. The app sets it once the window is open.
    @ObservationIgnored public var filePicker: (any FilePicker)?

    public init(themes: ThemeStore) {
        self.themes = themes
    }

    /// The theme being edited: the one shown.
    public var theme: ColorTheme { themes.current }

    /// Whether the shown theme can be changed: built-ins are read-only (spec §6.6).
    public var isEditable: Bool { !themes.isBuiltIn(theme.id) }

    /// Delete… is waiting for its confirmation. Setting it `false` is the confirmation's Cancel.
    public var isConfirmingDelete: Bool {
        get { pendingDeleteID != nil }
        set { if !newValue { pendingDeleteID = nil } }
    }

    /// The confirmation's title: it names the theme it would delete.
    public var deleteTitle: String {
        "Delete “\(pendingDeleteID.flatMap { themes.theme($0) }?.name ?? theme.name)”?"
    }

    /// The name field's text: what was typed for this theme, else its name.
    public var nameText: String {
        if let nameDraft, nameDraft.id == theme.id { return nameDraft.text }
        return theme.name
    }

    /// View ▸ Theme ▸ Edit Themes…. It says which theme files couldn't be read, if any.
    public func open() {
        isOpen = true
        message = themes.loadProblems.isEmpty ? nil : themes.loadProblems.joined(separator: " ")
    }

    /// Done (or Escape): commits a typed name, then closes.
    public func close() {
        commitName()
        isOpen = false
        pendingDeleteID = nil
    }

    /// Shows the theme with `id`, from the editor's menu or View ▸ Theme.
    public func select(_ id: ColorTheme.ID) {
        let refusal = commitNameKeepingRefusal()
        themes.select(id)
        message = refusal
    }

    /// A keystroke in the name field.
    public func typeName(_ text: String) {
        nameDraft = (theme.id, text)
    }

    /// Return in the name field, or the field losing focus: renames the theme the name was typed for, even if
    /// another is shown by now. A refused name says why and the field shows the theme's name again.
    public func commitName() {
        guard let draft = nameDraft else { return }
        nameDraft = nil
        perform { () throws(ThemeProblem) in try themes.rename(draft.id, to: draft.text) }
    }

    /// Commits a typed name for an action that follows (select, duplicate, import, export) and returns the refusal
    /// if the name was refused, so the action's own success doesn't wipe it: the person still learns why the name
    /// didn't stick.
    private func commitNameKeepingRefusal() -> String? {
        guard nameDraft != nil else { return nil }
        commitName()
        return message
    }

    /// Duplicate: an editable copy of the shown theme, shown at once.
    public func duplicate() {
        let refusal = commitNameKeepingRefusal()
        if perform({ () throws(ThemeProblem) in _ = try themes.duplicate(theme.id) }) { message = refusal }
    }

    /// Delete…: asks first, about the shown theme.
    public func requestDelete() {
        guard isEditable else { return }
        pendingDeleteID = theme.id
    }

    /// The confirmation's Delete: deletes the theme it asked about, never one chosen since; if that one is shown,
    /// Dracula is shown instead.
    public func confirmDelete() {
        guard let id = pendingDeleteID else { return }
        pendingDeleteID = nil
        if nameDraft?.id == id { nameDraft = nil }
        perform { () throws(ThemeProblem) in try themes.delete(id) }
    }

    /// One role's new colour, from its colour picker.
    public func setColor(_ color: HexColor, for role: ThemeRole) {
        perform { () throws(ThemeProblem) in try themes.setColor(color, for: role, in: theme.id) }
    }

    /// The colour picker's binding for `role`: the shown theme's colour, and `setColor` for each write.
    public func colorBinding(for role: ThemeRole) -> Binding<Color> {
        Binding(get: { [self] in theme.colors[role].color }, set: { [self] in setColor(HexColor($0), for: role) })
    }

    /// The Dark controls toggle.
    public func setDark(_ isDark: Bool) {
        perform { () throws(ThemeProblem) in try themes.setDark(isDark, in: theme.id) }
    }

    /// Import…: the open panel, then the chosen `.mctheme` file as a new theme, shown at once.
    public func importTheme(using picker: any FilePicker) async {
        let refusal = commitNameKeepingRefusal()
        do {
            guard let url = try await picker.chooseFileToOpen([.mctheme]) else { return }
            if perform({ () throws(ThemeProblem) in _ = try themes.importTheme(from: url) }) { message = refusal }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Export…: the save panel, then the shown theme (built-in or custom) as a `.mctheme` file.
    public func exportTheme(using picker: any FilePicker) async {
        let refusal = commitNameKeepingRefusal()
        let theme = theme
        do {
            guard let url = try await picker.chooseDestination([.mctheme], defaultName: "\(theme.name).mctheme") else { return }
            if perform({ () throws(ThemeProblem) in try themes.exportTheme(theme.id, to: url) }) { message = refusal }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Runs `action` with the window's file picker, from a button.
    public func withFilePicker(_ action: @escaping @MainActor (any FilePicker) async -> Void) {
        guard let filePicker else { return }
        Task { await action(filePicker) }
    }

    /// Runs a store action: success clears the message, a problem shows it. Returns whether it succeeded.
    @discardableResult
    private func perform(_ action: () throws(ThemeProblem) -> Void) -> Bool {
        do {
            try action()
            message = nil
            return true
        } catch {
            message = error.message
            return false
        }
    }
}
