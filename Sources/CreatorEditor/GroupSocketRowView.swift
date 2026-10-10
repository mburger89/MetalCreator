import CreatorGraph
import MetalUI

/// One socket in the inspector's list for Group Input or Group Output: its name (edit to rename), and buttons to move
/// it up or down and to remove it.
struct GroupSocketRowView: Component {
    let panel: GroupPanel
    let side: GroupSocketSide
    let socket: GroupPanel.SocketRow
    let model: EditorModel

    var content: some ElementGroup {
        HStack(spacing: Pixels(4)) {
            TextEntry(model: model, text: socket.name.rawValue, width: 110) {
                model.renameGroupSocket(panel.definition, side: side, from: socket.name, to: $0)
            }
            Spacer()
            Button("↑") { model.moveGroupSocket(panel.definition, side: side, named: socket.name, by: -1) }
                .help("Move up")
                .disabled(!socket.canMoveUp)
            Button("↓") { model.moveGroupSocket(panel.definition, side: side, named: socket.name, by: 1) }
                .help("Move down")
                .disabled(!socket.canMoveDown)
            Button("Remove") { model.removeGroupSocket(panel.definition, side: side, named: socket.name) }
                .help("Remove this socket and its wires inside")
        }
    }
}
