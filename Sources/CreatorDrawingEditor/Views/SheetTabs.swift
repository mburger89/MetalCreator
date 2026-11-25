import CreatorDrawing
import CreatorStyle
import MetalUI

/// The sheet tabs (plan R22): one per sheet in tab order, a "+" that adds a sheet, a click that shows one, a double click that
/// renames it in place (the field opens with the whole name selected; Return or losing focus commits one "Rename Sheet", Esc
/// none) and a context menu of Rename, Duplicate, Delete, Move Left and Move Right (the first tab can't move left, the last
/// can't move right). Showing a sheet is not an edit.
public struct SheetTabs: Component {
    let model: DrawingEditorModel
    @Environment(ThemeStore.self) var themes: ThemeStore?

    public init(model: DrawingEditorModel) {
        self.model = model
    }

    public var content: some ElementGroup {
        let colors = DrawingColors(themes)
        let sheets = model.document.sheets
        HStack(spacing: Pixels(4)) {
            ForEach(sheets, id: \.id) { sheet in
                if let rename = model.renaming, rename.sheet == sheet.id {
                    SheetRenameField(model: model, rename: rename)
                } else {
                    SheetTab(model: model, sheet: sheet, isCurrent: sheet.id == model.currentSheet, colors: colors)
                }
            }
            Button("Add Sheet") { model.addSheet() }
                .help("Add a sheet")
        }
    }
}

/// One tab.
struct SheetTab: Component {
    let model: DrawingEditorModel
    let sheet: DrawingSheet
    let isCurrent: Bool
    let colors: DrawingColors

    var content: some ElementGroup {
        let sheets = model.document.sheets
        let index = sheets.firstIndex { $0.id == sheet.id } ?? 0
        HStack(spacing: Pixels(0)) {
            Text(sheet.name).font(.callout).foregroundStyle((isCurrent ? colors.onAccent : colors.primary).color)
        }
            .padding(Edges(top: Pixels(4), right: Pixels(10), bottom: Pixels(4), left: Pixels(10)))
            .background((isCurrent ? colors.accent : colors.field).color, in: RoundedRectangle(cornerRadius: Pixels(5)))
            // A press and release, not a tap: a tap waits to see whether a second one follows, and a tab shows at once.
            .gesture(DragGesture(minimumDistance: Pixels(0)).onEnded { _ in model.selectSheet(sheet.id) })
            .simultaneousGesture(TapGesture(count: 2).onEnded { model.beginRenaming(sheet.id) })
            .contextMenu {
                Button("Rename") { model.beginRenaming(sheet.id) }
                Button("Duplicate") { model.duplicateSheet(sheet.id) }
                Button("Delete") { model.deleteSheet(sheet.id) }
                Button("Move Left") { model.moveSheet(sheet.id, by: -1) }
                    .disabled(index == 0)
                Button("Move Right") { model.moveSheet(sheet.id, by: 1) }
                    .disabled(index == sheets.count - 1)
            }
    }
}

/// The field a tab's name is typed into: it takes focus as it appears, opens with the name all selected, commits on Return and
/// when it loses focus, and Esc leaves the name as it was.
struct SheetRenameField: Component {
    let model: DrawingEditorModel
    let rename: SheetRename
    @FocusState var isFocused: Bool

    var content: some ElementGroup {
        TextField("Name", text: rename.draft, selection: rename.selection,
                  onChange: { model.renameDraftChanged($0) },
                  onSelectionChange: { model.renameSelectionChanged($0) })
            .font(.callout)
            .focused($isFocused)
            .onKeyPress(.escape) {
                model.cancelRename()
                return .handled
            }
            .onSubmit { model.commitRename() }
            .frame(width: Pixels(120))
            .onAppear { isFocused = true }
            .onChange(of: isFocused) { wasFocused, focused in
                if wasFocused, !focused { model.commitRename() }
            }
    }
}
