# Connecting an AI client (MCP)

MetalCreator can let an AI client such as Claude Code or the Claude desktop app work with the document open in the running
app: read the graph and what each node made, build and edit it, open, save and export files. You watch every edit happen in
the window and can undo it. Spec: `docs/superpowers/specs/2026-11-08-mcp-server-design.md`.

## Turning it on

It is off until you turn it on. Choose **MetalCreator ▸ Allow AI Connections** (the File menu on Linux and Windows); the choice
is remembered. Or launch with `--mcp` (`MetalCreator --mcp`) to turn it on for that launch. While a client is connected an
"AI connected" chip shows in the window. Nothing listens on a network port: the app listens on a local socket only you can open.

The client does not talk to the app directly. It starts the small program `metalcreator-mcp` (the bridge), which speaks MCP
over stdin and stdout and forwards to the app. When the app is not running or the switch is off, the bridge says so itself
("MetalCreator isn't running, or AI connections are off"). It connects to the app when the client first asks something, then keeps
trying in the background (every second) and announces the tools when the app appears or comes back, so you can start the client
first and quit or relaunch the app without reconnecting.

The app serves one client at a time. If another is connected, a second one is told "MetalCreator is already connected to another
AI client. Disconnect that one, then try again." within a couple of seconds, and connects by itself when the first leaves.

The menu item tells you when the connection can't be made. "AI Connections: in use by another window" means another
MetalCreator window already serves the socket; "AI Connections: couldn't start (reason)" means the listener failed (the reason
says why, for instance a folder that isn't private). Choose the item again to try again, for instance after closing the other
window, or choose **Turn Off AI Connections**, which appears under it in these two states, to switch the connection off (even
under `--mcp`).

## Claude Code

macOS:

    claude mcp add metalcreator -- /Applications/MetalCreator.app/Contents/MacOS/metalcreator-mcp

Linux (the tarball; the helper sits beside `MetalCreator`):

    claude mcp add metalcreator -- /path/to/MetalCreator/metalcreator-mcp

The AppImage mounts itself at a new path on every run, so a path inside the running AppImage does not last. Use the tarball's
helper, or extract the AppImage once (`./MetalCreator.AppImage --appimage-extract`) and point at the extracted copy:

    claude mcp add metalcreator -- /path/to/squashfs-root/usr/metalcreator/metalcreator-mcp

Windows:

    claude mcp add metalcreator -- C:\Path\To\MetalCreator\metalcreator-mcp.exe

## Claude desktop app

Add to `claude_desktop_config.json` (Settings ▸ Developer ▸ Edit Config), with your path to the bridge, then restart it:

    {
      "mcpServers": {
        "metalcreator": { "command": "/Applications/MetalCreator.app/Contents/MacOS/metalcreator-mcp" }
      }
    }

## The socket

The app listens on `mcp.sock`: macOS `~/Library/Application Support/MetalCreator/Connection/mcp.sock` (a 0700 folder the app
owns); Linux `$XDG_RUNTIME_DIR/metalcreator/mcp.sock`, else `/tmp/metalcreator-<uid>/mcp.sock`; Windows
`%LOCALAPPDATA%\MetalCreator\mcp.sock`. The file is 0600 where the platform has permissions. `metalcreator-mcp --socket <path>`
uses another. The bridge holds no connection to the app until its client's first request. A request in flight when the app quits is answered "MetalCreator closed the connection before answering."

## Tools

Reading (works in every mode):
- `get_document`: the open document's nodes (each with its state, whether it is an Output (`is_output`) and a one-line summary of
  each output socket under `outputs`; a solid reads "solid: 6 faces, 12 edges, bounds (0, 0, 0) to (60, 40, 5) mm", a list of solids "3 solids"), links, parameters and groups, 200 nodes at a time.
- `get_node`: one node's inputs (each with `source`: `wired`, `set` (stored, even if equal to the default), `default` or `unset`, and its `value`), outputs (summary, and for solids a `solids` array of `{faces, edges, bounds_min, bounds_max}`, the first 20, with `solids_total` when more), `is_output`, state and settings.
- `list_node_types`: the node types you can add, optionally of a category or matching a search.
- `describe_node_type`: a type's inputs with defaults, units, ranges and options, its outputs and settings.

Editing (each call is one named undo step):
- `add_node`: add a node of a type, optionally named, placed and with inputs set.
- `set_inputs`: set a node's constant input values; null clears one.
- `connect` / `disconnect`: wire an output into an input (replacing any wire there) or remove the wire.
- `remove_nodes`: delete nodes and their wires.
- `rename_node`, `set_output` (mark or unmark an Output), `move_node`.
- `set_file`: set the file of an Image Field (a picture) or an Import Mesh node (STL or 3MF), linked or embedded.
- `batch`: several edit operations as one undo step, or none if any is refused. The step is named "Build" (it adds a node), "Delete", "Rewire", "Rearrange" or "Edit Graph", or after its one operation; an optional `step_name` picks one of Build, Rewire, Rearrange, Clean Up, Delete or Edit Graph (no other text).

Edit results list each `changed` node (state or outputs changed) with its `outputs` summaries.

History:
- `undo` / `redo`: take back or re-apply the client's own last step.

Files:
- `new_document`, `open_document`: refused while the open document has unsaved changes unless `discard_unsaved` is true.
- `save_document`: to the document's own file or an absolute path; will not overwrite a file unless `overwrite` is true.
- `export`: the Output nodes' results as step, stl or 3mf. The nodes' warnings come back in the result's message; no alert is raised in the window.

Resources: `metalcreator://document` and `metalcreator://node-types`.

## Rules

- **Units.** Numbers are the stored units whatever the document displays: lengths in millimetres, angles in degrees, counts as integers. Nothing a client writes is converted.
- **Which graph.** A client works on the top-level graph, whatever level you have entered. A group node is an ordinary node to it; editing inside a group definition, Group, Ungroup and Make Unique are not offered.
- **Modes.** Edits and file tools are refused with a sentence while you are sketching, picking, using the model dimension tool, an alert is up, the export window is open, a file open/save panel is up, the app is checking a change, a slider or handle is being dragged, or something is being moved on the canvas. A pending typed value is committed first and counts as unsaved work. Reading tools always work.
- **Undo is the client's own.** `undo` and `redo` only take back steps the client made (remembered in memory, not in the file); when the step on top is yours the client is told, naming it. Your own Undo takes back anything. A client's edits never merge into one another.
- **Paths** must be absolute. No unsaved document is discarded and no file overwritten unless the call says so.
- **No picks yet.** Edge and face picks are not settable; a client chooses edges with the selection-rule nodes (Edges by Direction, Edges by Tag). Drawing a sketch's entities is not offered.
- **Nothing is saved from MCP** in a `.mcgraph`; the file format is unchanged. The server runs only in the normal windowed launch, never under `--self-test`, `--smoke-test` or headless.
