# MetalCreator MCP server: design

Date 2026-11-08. Status: draft for the user's approval. Reviewed by a builder check; its questions are answered in §4 "Rules every tool follows".

## 1. Intent

The user: "I want to add an mcp to this app." The user asked to skip question rounds for designs on this project, so every
choice below that the user didn't state is marked **(our call)**.

MetalCreator gets a Model Context Protocol (MCP) server, so an AI client (Claude Code, the Claude desktop app, any MCP client)
can work with the document open in the running app. The client can read the graph and its results, build and edit graphs,
open, save and export files, and later see the viewport. The person watches the edits happen in the window and can undo any of them.

Why: the graph is easy for a model to reason about (typed nodes, sockets, values, errors in words), and a model that can drive
the app can build parts from a description, fix a failing node from its message, and sweep a parameter. A second use **(our
call)**: our own human checks can drive the app through MCP instead of a mouse, for everything that isn't about how the
screen looks.

## 2. Goals, non-goals, anti-goals

Goals:
- Clients act on the running app's open document, and the window shows every change as if a person had made it.
- Every edit is one named undo step, so ⌘Z takes back what the model did, step by step.
- The client reads back what a node made: its state, warning or error text, and a short summary of each output.
- The same server on macOS, Linux and Windows.
- Off until the person turns it on.

Non-goals (this design):
- An assistant or chat panel inside MetalCreator (MetalCreator as an MCP *client*). That is a separate project.
- Editing sketches entity by entity (lines, constraints). A Sketch node's exposed dimensions are in scope; drawing is not.
- Editing inside group definitions, and Group, Ungroup and Make Unique (a later step).
- Setting edge and face picks by hand (they come with the pictures, MCP-2).
- Remote access over a network, and more than one client editing at once.

Anti-goals (a failure even if it works):
- A client changes or loses the person's work silently. No unsaved document is discarded, and no file is overwritten,
  unless the call says so explicitly.
- Anything listening on a network port.
- The window freezing while a client works. Requests run on the main actor between frames, and long work is awaited, never blocked on.

## 3. Shape

Three parts **(our call)**:

1. **`CreatorMCP`** (a new library target, portable, no Apple-only imports): MCP's JSON-RPC 2.0 messages, the tool
   catalogue and the handlers. A handler takes a `DocumentSession` (below) and JSON arguments, and returns JSON content
   or an MCP tool error. It knows nothing about sockets. It depends on `CreatorGraph`, `CreatorKernel` and `CreatorGeometry`, and
   reaches the app only through the `DocumentSession` protocol.
   We write the protocol layer ourselves rather than adding the official Swift SDK, because the subset we need is small
   (initialize, ping, tools/list, tools/call, notifications/initialized) and the repo has no external dependencies besides
   MetalUI. The builder may revisit this if the SDK builds cleanly on all three platforms with no transitive dependencies.
2. **The server in the app** (`CreatorApp`): a local socket listener started by `MetalCreatorApp/main.swift` when MCP is
   on. It accepts one connection at a time and reads newline-delimited JSON-RPC (MCP's stdio framing). It hands each request
   to the main actor, where `AppModel` implements `DocumentSession`, and writes the response back. The accept loop and reads
   run on their own thread, never on the main actor.
3. **`metalcreator-mcp`** (a new small executable, shipped beside the app's executable in the macOS bundle, the Linux tarball
   and AppImage, and the Windows zip): a stdio bridge. Clients are configured with its path (for example
   `claude mcp add metalcreator -- /Applications/MetalCreator.app/Contents/MacOS/metalcreator-mcp`). It copies stdin to the
   socket and the socket to stdout. If the app isn't running or MCP is off, it answers the client's `initialize` itself with a
   clear error ("MetalCreator isn't running, or MCP is off: turn it on in MetalCreator ▸ Allow AI Connections").

Transport **(our call)**: a Unix domain socket on all three platforms (Windows 10 and later support `AF_UNIX`). The socket
file is in the app's per-user support folder (macOS `~/Library/Application Support/MetalCreator/Connection/mcp.sock`, a 0700 folder the app owns and tightens; Linux
`$XDG_RUNTIME_DIR/metalcreator/mcp.sock`, Windows `%LOCALAPPDATA%\MetalCreator\mcp.sock`), created with permissions
0600 where the platform has them. No TCP port, so nothing is reachable from another machine. A stale socket file from a
crashed run is removed at start. A second app instance doesn't start a second server; MetalUI's single-instance forwarding
already sends launches to the first.

Turning it on **(our call)**: a checkable menu item, "Allow AI Connections" (app menu on macOS, the File menu elsewhere), saved
as a per-user preference and off by default, plus a `--mcp` launch flag for one session. While a client is connected,
the top bar shows a small "AI connected" chip (a `GlassPanel(.chip)`, like the slow-evaluation chip), so the person always
knows.

## 4. Tools (MCP-1)

Names are snake_case. Nodes are addressed by ID (the full UUID string) or by unique name. Sockets are addressed by name.
Every edit tool waits for the evaluation it caused (`AppModel.settle()`, capped at 60 s; past that it returns with the nodes
still evaluating marked as such) and returns the state of every node whose state changed: `ok`, `warning` plus its text,
`error` plus its text, or `evaluating`.

Reading:
- `get_document`: file name or "Untitled", whether edited, units, the nodes (ID, name, type, position, state and message,
  output flag), the links, the parameters, the group definitions by name. Large graphs are paged.
- `get_node`: one node's inputs (name, type, unit, value or "wired from X.socket", default), its outputs with a one-line
  summary each (the text the inspector and the socket tooltips already build: `socketHelp`, `fieldSummary`, the
  implicit and mesh facts, a solid's face and edge counts and bounding box), its state and message.
- `list_node_types`: every type in the registry, filterable by category and by a search string, with display name,
  category, sub-group and a one-line description.
- `describe_node_type`: a type's inputs and outputs (name, socket type, default, unit, range, options of a segmented
  choice) and its settings.

Editing (each one undo step, named with the existing `UndoName` constants and functions, never with text from the client):
- `add_node(type, name?, position?, inputs?)`: makes it with `NodeRegistry.makeNode`. Without a position it is placed by the
  editor's free-position rule, so it doesn't land on another node.
- `set_inputs(node, values)`: one or more inputs in one step. Values are plain JSON coerced by the socket's type: a number,
  an integer, a bool, a vector `[x, y, z]`, the option's name or index for a choice, a string for a text setting, or `null` to clear.
- `connect(from: "node.socket", to: "node.socket")` and `disconnect(to: "node.socket")`: refusals use
  `connectionProblem`'s own words.
- `remove_nodes(nodes)`, `rename_node(node, name)`, `set_output(node, bool)`, `move_node(node, position)`.
- `undo` and `redo`: return the name of the step taken back or redone.
- `batch(operations)`: a list of the edits above applied as one undo step ("Edit" would fail the naming rule, so the step
  is named after its first operation's name, as a coalesced run is).

Files:
- `new_document(discard_unsaved?)`, `open_document(path, discard_unsaved?)`: refuse when the open document has
  unsaved changes unless `discard_unsaved` is true. They never raise the app's own alerts.
- `save_document(path?, overwrite?)`: saves to the document's file, or to `path`. An existing file other than the document's own
  is refused unless `overwrite` is true.
- `export(kind, path, overwrite?)`: `step`, `stl` or `3mf`, through `AppModel.export(_:to:)`, with the same overwrite rule.
  Long exports report MCP progress notifications when the client sent a progress token.
- Paths must be absolute. Relative paths are refused, not resolved.

Rules every tool follows (settled after the builder check, all **(our call)**):
- **Which graph.** A client reads and edits the top-level graph, whatever level the person has entered. Group nodes are
  ordinary nodes to it: it can add a group node by its definition's name, wire it and set its inputs, and `get_document`
  lists each definition with its interface. Editing inside a definition, and Group, Ungroup and Make Unique, are not in
  MCP-1. After a client edit the editor refreshes its level (`refreshLevel()`), as it does after undo.
- **Units.** Numbers are always the stored units, whatever the document displays: lengths in millimetres, angles in
  degrees (`ValueUnit`), counts as integers. `get_document` reports the display units for information, and
  `describe_node_type` and `get_node` name each input's unit. Nothing a client writes is converted.
- **Modes.** An edit or file tool is refused with a sentence while sketch mode, a pick session, the model dimension tool
  or an app alert (Save / Don't Save, an error) is up: "MetalCreator is editing a sketch. Click Finish in the sketch toolbar, then
  try again." A pending text entry in the inspector or on the canvas is committed first, as save and undo commit it, and an
  open add-node palette is closed. Measure, the section and zebra are view state and stay as they are. Reading tools work
  in every mode.
- **Settings beyond sockets.** In MCP-1 a client sets socket values and the text settings (Path Mapper's rule, Branch by
  Path's and List Item's paths, Cull Pattern's mask, Cull Index's indices), an exposed sketch dimension (a socket), and an
  Image Field's picture or an Import Mesh node's file by absolute path, linked, or embedded with `embed: true`. Edge and
  face picks are not settable: a client chooses edges with the selection-rule nodes (Edges by Direction, Edges by Tag),
  and picking by sight comes with the pictures (MCP-2). Drawing a sketch's entities is a non-goal (§2).
- **Undo.** A client's edits never coalesce, and one arriving mid-drag (`isScrubbing`, an open slider run) is refused
  ("The person is changing a value; try again in a moment."). The `undo` tool takes back only a step a client made: the
  app remembers the undo entries its client steps produced (in `AppModel`, in memory; nothing in `CreatorGraph` or the
  file), and `undo` refuses when the step on top is the person's ("The last step is yours, not mine: Undo Move."). `redo`
  likewise. The person's ⌘Z takes back anything, as now.
- **Where it runs.** Only in the normal windowed launch, never under `--self-test`, `--smoke-test` or headless. The
  end-to-end test drives the server over a real socket in a test process with a `DocumentSession` over `DocumentModel`
  and `FakeKernel`; the human checks drive the real app.
- **Second instance and stale sockets.** At start the server first tries to connect to an existing socket: if one answers,
  another MetalCreator owns it, and this one doesn't serve (its menu item reads "AI Connections: in use by another
  window"). Only a socket that refuses the connection is removed as stale.
- **Linux without `XDG_RUNTIME_DIR`.** The socket goes in `/tmp/metalcreator-<uid>/`, a folder made with permissions 0700
  and refused if it exists with another owner or wider permissions.
- **Undo names.** New `UndoName` constants for the steps that have none yet ("Rename Node", "Set Output" and so on), named
  by fixed words as the rules require.

Errors: a tool that can't do what was asked returns an MCP tool result with `isError: true` and a sentence in the app's
voice (as node messages are worded). Malformed JSON-RPC gets JSON-RPC errors.

Resources (MCP-1, small): `metalcreator://document` (the same text as `get_document`) and
`metalcreator://node-types` (the catalogue), so a client can read without calling tools.

## 5. Pictures (MCP-2, a separate sub-project)

`get_view_image(width?, height?, camera?)`: the 3D viewport drawn offscreen as a PNG (MCP image content), with an optional
named camera (`front`, `top`, `iso`, or the current one), and `get_window_image` for the whole window. This needs new code:
render to an offscreen target (`renderFrame` plus the viewport renderer on Metal; the SDL renderer's `download` on Linux and
Windows), read the pixels back, and a PNG encoder in a source target (the test-only `PNGWriter` moved and given real deflate, or
ImageIO under `#if canImport(ImageIO)`). It merges on its own after MCP-1.

## 6. Constraints

- Swift 6 strict concurrency: every read and edit runs on the main actor. Results crossing threads are `Sendable` JSON
  values. No `@unchecked Sendable` to silence a diagnostic.
- The cross-platform rules in CLAUDE.md apply (no CryptoKit, no unguarded Apple frameworks, `ContentType` declares its extensions).
  Socket code is POSIX on macOS and Linux and Winsock on Windows, behind `#if os(...)`, in one small file each.
- No new external package dependencies (see §3 for the one exception the builder may weigh).
- Tests: Swift Testing. `CreatorMCPTests` exercise every tool over a `DocumentModel` with `FakeKernel` through an in-memory
  session (no socket), plus a transport test over a real socket pair and an end-to-end test of the bridge against a test
  server. The suite pass rules (12 "Test run with" lines today, 13 with the new target) apply on all three platforms.
- The file format doesn't change. MCP state is never saved in `.mcgraph`.
- The undo-name rules hold (no typed text, no numbers).
- Docs: `docs/mcp.md` (turning it on; configuring Claude Code and the Claude desktop app; the tool list), and a CLAUDE.md
  paragraph. Human checks group MCP in `docs/verification/human-checks.md`: connect from Claude Code, build a plate with holes
  by asking, watch it appear, undo it step by step.

## 7. Left to the builder

- The exact JSON shapes of each tool's input schema and result, within §4.
- Where the "AI connected" chip sits (beside the slow-evaluation chip is the default).
- The per-platform preference storage for the on/off switch (the app's existing preference mechanism).
- The MCP protocol version to announce (the newest the client offers that we support; 2025-06-18 at least).

## 8. Order of work

MCP-1 (protocol, server, bridge, the tools of §4, the switch and the chip, docs) merges on its own. MCP-2 (pictures) follows.

## Errata

- 2026-11-09 (R9, socket paths): the macOS socket is `~/Library/Application Support/MetalCreator/Connection/mcp.sock`, in a
  folder of its own that the app creates 0700 and tightens to 0700 if it finds it wider (a folder another user owns, a symlink or
  a file is refused); §3 above is amended to match. The socket file itself is `chmod`ed 0600 after `bind`; the process-wide
  `umask` is not touched.

- 2026-11-10 (sketch refusal wording): the sketch toolbar's button is labelled Finish, not Done, so the refusal in §Modes now reads "MetalCreator is editing a sketch. Click Finish in the sketch toolbar, then try again." (the line above is amended to match).
