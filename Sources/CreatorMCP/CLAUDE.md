# CreatorMCP (the MCP server and bridge)

Notes for this module, moved from the root `CLAUDE.md` (which Claude Code loads in every session) so they load only when work touches this folder. The project-wide rules, commands and toolchain notes stay in the root file.

MCP server, MCP-1 (an AI client works with the open document: spec `docs/superpowers/specs/2026-11-08-mcp-server-design.md`, plan
`docs/superpowers/plans/2026-11-08-mcp-1.md`, user docs `docs/mcp.md`; `CreatorMCP` is the portable protocol, tools, socket transport and
`MCPBridge`; the app side is `Sources/CreatorApp/MCP`: `MCPService`, `AppDocumentSession` (the `DocumentSession` the tools drive, on the main
actor), `MCPPreference` and the "Allow AI Connections" toggle (app menu on macOS, File menu elsewhere; off until chosen) or the `--mcp` flag,
and the "AI connected" chip; never under `--self-test`, `--smoke-test` or headless) code is done; its human checks (group MCP) are pending.
The server listens on a Unix socket, not a port: macOS `~/Library/Application Support/MetalCreator/Connection/mcp.sock` (a 0700 folder),
Linux `$XDG_RUNTIME_DIR/metalcreator/mcp.sock` else `/tmp/metalcreator-<uid>/mcp.sock`, Windows `%LOCALAPPDATA%\MetalCreator\mcp.sock`, the
file 0600 where the platform has permissions. Clients start the bridge product `metalcreator-mcp` (target `MetalCreatorMCPBridge`,
`Sources/metalcreator-mcp`; shipped beside `MetalCreator` in the app bundle's `Contents/MacOS`, the Linux tarball and AppImage and the Windows
zip, and checked by `scripts/verify-app.sh`), which answers by itself when the app isn't reachable, retries before each request and announces
`notifications/tools/list_changed` once it connects. Rules: numbers are stored units (mm, degrees); a client's edits are refused while an alert is up, the export sheet or a document file panel (`FilePanelActivity`, `AppModel.tracked(_:)`) is up, results are held, sketching,
picking, adding a model dimension, a slider or handle is dragged or something is moved on the canvas (a pending typed value is
committed first); each edit is one named undo step that never coalesces, and the client's `undo`/`redo` take back only its own steps (in-memory
serials on undo entries, nothing saved); nothing MCP is in `.mcgraph`; no edge or face picks yet; the drawing tools (`list_drawings`, `get_sheet`, `export_drawing`, DR-5) read and export and place nothing.
MCP-1b (plan `docs/superpowers/plans/2026-11-13-mcp-1b-followups.md`) code is done; its human checks (MCP-8 to MCP-13) are pending:
the bridge connects at its client's first request (never at start) and a watcher retries every second, announcing `list_changed` when the app
appears or returns; a second client gets JSON-RPC error `-32001` "MetalCreator is already connected to another AI client. Disconnect that one,
then try again." (the listener waits a 1 s grace for the slot); "Turn Off AI Connections" shows in the `.inUse` and `.failed` states (also under
`--mcp`); edits are refused behind the export sheet, a file panel and held results; a solid's output summary reads "solid: N faces, M edges,
bounds (…) to (…) mm" and `get_node` inputs carry `source` (wired, set, default, unset) and outputs a `solids` array; `batch` takes a
`step_name` from the fixed `UndoName.clientBatchNames` and otherwise names itself from its contents; `GraphError.message`, `SocketLabel` and
`CanvasMetrics.nodeWidth` live in `CreatorGraph`; `package-linux.sh` scans and bundles the bridge's libraries too.

- `CreatorMCP`: the Model Context Protocol server (MCP-1; `docs/mcp.md`). Portable (declared everywhere); depends on `CreatorGraph`, `CreatorKernel`,
  `CreatorGeometry` and `CreatorDrawing`, **never on the editor or the app**: the tools drive a `DocumentSession` protocol that `CreatorApp`'s `AppDocumentSession`
  implements (tests use one over `DocumentModel` and `FakeKernel`). Our own JSON-RPC subset (`initialize`, `notifications/initialized`, `ping`,
  `tools/list`, `tools/call`, `resources/list`, `resources/read`; `JSONValue`), `MCPCatalogue` (the tools: `Tools/`), the socket transport (one small
  file per OS family) and `MCPBridge` (the `metalcreator-mcp` executable's logic). Tool errors are full sentences in the app's voice, returned
  with `isError: true`. Tests: `swift test --filter CreatorMCPTests`.
