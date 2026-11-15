# MCP-1b: follow-ups from checking and using the MCP server — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Fix what MCP-1's checks and first real use turned up: the bridge connects by itself when the app appears, a second client is refused promptly, the menu can switch the server off from its error states, client edits are refused during the export sheet, file panels and held results, output summaries say what a solid is, `get_node` tells a set input from a default, a batch gets a fitting undo name, and the duplicated logic and the Linux bridge scan are cleaned up.

**Spec:** `docs/superpowers/specs/2026-11-08-mcp-server-design.md` (plus the 2026-11-13 erratum written in Track D). Parent plan: `docs/superpowers/plans/2026-11-08-mcp-1.md`.

**Branch/worktree:** `mcp-1b` at `/Users/maxburger/Developer/mcp-1b/MetalCreator`; MetalUI is the sibling `../MetalUI` at the CI pin (never edit or move it). Tracks run one after another in this order; a later track may use an earlier one's names. One commit per task, messages ending in exactly:

    Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
    Claude-Session: https://claude.ai/code/session_0195iKYokoi2BJLpboZBys76

## Global constraints

- Swift 6 strict concurrency; Swift Testing; `swiftlint lint --strict` clean. No loop holding locals across an `await` (Windows compiler notes in CLAUDE.md). No `@unchecked Sendable`.
- No new file format change, nothing MCP in `.mcgraph`. `CreatorMCP` must not import `CreatorEditor` or `CreatorApp`; it may import `CreatorGraph`, `CreatorKernel`, `CreatorGeometry`.
- Suite rules unchanged (13 "Test run with" lines; none "recorded an issue" or "failed after"). Do not run the Linux Docker suite. Run `swift test --filter CreatorMCPTests`, `--filter CreatorAppTests.MCP...` (the MCP suites in `Tests/CreatorAppTests/MCP`), `CreatorGraphTests`, `CreatorEditorTests` as each track touches them.
- Docker: create none; if one is ever made, delete it once its result is read.
- Never quit or kill any process; the user's MetalCreator.app is running. Tests must use temp socket paths (`tempSocketURL()`), never the real `mcp.sock`.

## Rulings

Each is "Ruling: decision — why — cost if wrong".

- **R1 (what holds the app's one slot).** Ruling: a bridge connects to the app only when its client has sent its first request (`initialize`), never at process start. — Today every launched bridge connects at start and holds the single slot even if its client never speaks, which is a cause of item 2 and would make item 1's background retry worse. — Cost if wrong: the first request pays one connect (milliseconds) and the chip appears at `initialize` rather than at bridge start; nothing else changes.
- **R2 (background retry).** Ruling: once the client has initialized, a watcher thread in the bridge retries the connection every 1 s (injectable `retryInterval`) whenever there is no live link, replays `initialize` + `initialized` on success, and sends `notifications/tools/list_changed` and `notifications/resources/list_changed` once per gap; it also does this after a link was lost (app quit and relaunched), where the bridge fails pending requests as now and announces on reconnect. — This is "keep trying" without a protocol change and without holding anything before the client speaks. — Cost if wrong: one `stat` + failed `connect` per second while the app is down; negligible.
- **R3 (second client).** Ruling: the listener serves one client at a time as now, but a connection that arrives while the slot is taken waits up to a 1 s grace (a client restarting releases the slot late) and is then answered, on its first request line, with a JSON-RPC error `code -32001` and the sentence "MetalCreator is already connected to another AI client. Disconnect that one, then try again.", and closed. The bridge waits for the app's answer to its replayed `initialize` (up to 5 s; the answer is still never forwarded) and, on `-32001`, answers its own client's requests alone with that sentence (as `initialize` instructions, a `tools/call` error result, empty lists) and keeps retrying (R2), so the second client starts working when the first leaves. — A prompt, worded refusal replaces a silent 30 s timeout, and no client-side change is needed. — Cost if wrong: a refused client costs up to ~1 s of grace; the cap is a constant.
- **R4 (menu).** Ruling: in the `.inUse` and `.failed` states the menu shows the retry item as today and a second item "Turn Off AI Connections" (`MCPService.turnOff()`), which works under `--mcp` too (it is an explicit act; without it a stuck state under the flag is a trap). — Smallest change that adds the missing exit and keeps today's retry. — Cost if wrong: one extra menu item in error states only.
- **R5 (edit refusals).** Ruling: refuse when the export sheet is up (`model.exportRun != nil`), when any document file panel is up (open, save, import mesh, choose or relink image, export destination; counted by a new `FilePanelActivity`; the theme editor's import/export panels are not counted, they cannot change the document), and while results are held (`document.isHoldingResults`). They apply to every edit, undo, redo, new, open, save, export and set_file exactly as the alert rule does, in the order alert, export sheet, file panel, held results, sketch, pick, dimension, canvas drag, scrubbing. — Same mechanism, same call sites. — Cost if wrong: a stuck flag would refuse all edits; mitigated by `defer` counting and a test that a thrown picker releases it.
- **R6 (solid summaries).** Ruling: a single solid's summary string becomes `solid: 6 faces, 12 edges, bounds (0, 0, 0) to (60, 40, 5) mm` (singular "1 face", "1 edge"; numbers rounded to 4 decimals, stored mm); a list or tree of solids keeps "3 solids" in the summary string, and `get_node` additionally returns, per output, `solids`: an array of `{faces, edges, bounds_min, bounds_max}` (first 20, with `solids_total` when more). `get_document` gets the strings only (page size). Edit results' `changed` entries gain `outputs` (the same string map as `get_document`) when non-empty. — Strings are what a client reads first; structure only where a client asks for one node. — Cost if wrong: longer `get_document` lines.
- **R7 (set vs default).** Ruling: every `get_node` input gets `source`: `"wired"`, `"set"` (explicit stored value, even if equal to the default), `"default"` (nothing stored, the socket's default shows) or `"unset"` (nothing stored, no default). `value` stays present for `set` and `default` (clients already read it); `default` stays. — Additive, no client breaks. — Cost if wrong: none.
- **R8 (batch name).** Ruling: `batch` takes an optional `step_name` chosen from a fixed list (`UndoName.clientBatchNames`: "Build", "Rewire", "Rearrange", "Clean Up", "Delete", "Edit Graph"), never free text, because CLAUDE.md's undo-name rules say a name never carries typed text or numbers and a client's text would show in the person's Edit menu; any other value is refused naming the list. Without `step_name`: a batch of one operation keeps that operation's own name (as today); otherwise "Build" if it adds a node, "Delete" if it only removes nodes, "Rewire" if it only connects or disconnects, "Rearrange" if it only moves nodes, else "Edit Graph". — Meaningful in the menu ("Undo Build" rather than "Undo Add Rounded Rectangle") with zero typed text. — Cost if wrong: a client cannot say more than the list; widening it is a one-line change.
- **R9 (sharing).** Ruling: the three duplicates move down into `CreatorGraph`, the one module both sides already depend on: `GraphError.message`, `SocketLabel.text(for:)` (the inspector label rule; `InspectorLabel.text` and `ValueCoercion.label` forward or are removed) and `CanvasMetrics.nodeWidth = 224` (`NodeLayout.width` uses it). The 40 pt gap stays an MCP placement choice. — No new module, no dependency inversion. — Cost if wrong: none; pure moves with pinned values.
- **R10 (Linux scan).** Ruling: `package-linux.sh` runs the bundle-and-scan loop over both executables, checks the packaged bridge resolves with no "not found" under its `$ORIGIN/lib` rpath, and the clean-Ubuntu step of `linux-test.sh` runs the packaged bridge once. The macOS verifier already scans every Mach-O and runs the bridge; Windows already queues the bridge for its DLL scan (`package-windows.ps1`). — Closes the one platform that skipped it. — Cost if wrong: none.

---

## Track A

Connection: items 1, 2, 3. Files: `Sources/CreatorMCP/Bridge/MCPBridge.swift`, `Sources/CreatorMCP/Transport/MCPListener.swift`, `Sources/CreatorMCP/Protocol/JSONRPC.swift`, `Sources/CreatorApp/MCP/MCPService.swift`, `Sources/CreatorApp/AppCommands.swift`, `Sources/metalcreator-mcp/main.swift`; tests `Tests/CreatorMCPTests/BridgeTests.swift`, `TransportTests.swift`, `Tests/CreatorAppTests/MCP/MCPServiceTests.swift`.

### A1. Listener: one active client, a worded refusal for the next (item 2)

- `JSONRPC`: `static let alreadyConnected = -32001`.
- `MCPListener`: `public static let busySentence = "MetalCreator is already connected to another AI client. Disconnect that one, then try again."`; init gains `busyGraceMilliseconds: Int = 1_000` after `writeTimeoutMilliseconds`.
- The accept loop no longer serves inline. For each accepted connection it starts a short thread `admit(connection, run)`: try to claim the slot (`Mutex<Bool>` named `slot`); if taken, poll it every 20 ms for `busyGraceMilliseconds`; if claimed, `serve(connection, run)` (existing body) and release the slot in `defer`; if not, `refuse(connection)`: wait up to 1 s for a first line, and if one arrives write `JSONRPC.error(id: <its id or .null>, code: JSONRPC.alreadyConnected, busySentence)` with the send timeout set, then close; no line (a probe) just closes. `refuse` never calls `connectionChanged`.
- `runningLoops` still counts accept loops only. Add `var activeConnections: Int` (admit/serve threads alive; test read-back) and make `stop()` leave them to wind down on `run.isStopped` as `serve` already does.
- Update `onlyOneClientAtATime` (now: second client gets the refusal line within 3 s, then after the first closes a third client is served).

Tests (`TransportTests`):
- `secondClientIsRefusedWithTheBusySentence`: first client holds the slot; second sends `{"jsonrpc":"2.0","id":7,"method":"initialize"}`; reads one line; assert `error.code == -32001`, `error.message == MCPListener.busySentence`, `id == 7`; then the socket reads EOF. Listener built with `busyGraceMilliseconds: 100`.
- `aSlotFreedWithinTheGraceServesTheNextClient`: first client closes 100 ms after the second connects (grace 1 s): second is served normally (echo handler), no refusal line.
- `aProbeWhileBusyIsClosedQuietly`: second connection sends nothing and closes; first client unaffected; `states` shows no extra `true`/`false`.
- `refusalDoesNotChangeTheConnectionState`: the `states` recorder holds exactly `[true]` while a refused client came and went.
- `stopWithABusyAdmitThreadLeavesNoThread`: stop, then `activeConnections == 0` and `runningLoops == 0` within 5 s.

### A2. Bridge: connect on first request, watch in the background, read the refusal (items 1 and 2)

`MCPBridge.init(socketPath: URL, retryInterval: Duration = .seconds(1), handshakeTimeout: Duration = .seconds(5))`; `main.swift` is unchanged (defaults).

- `BridgeSession`: all state changes under one `NSLock` (`sync`), taken by `handle`, `waitForReplies`, `close` and the watcher's `poll()`. The reader thread never takes it.
- Remove the start-up `connectIfPossible(replayingInitialize: false)` from `run` (R1); a connect happens in `handle` for the first request, as for later ones.
- `run` starts a `Thread` "MCP bridge watcher": loop until stopped (checked every 50 ms while sleeping `retryInterval`) calling `session.poll()`. `poll()`: return unless `initializeParams != nil`; if `link?.hasEnded == true` → `dropLink()` (fails pending, as now) and `needsAnnounce = true`; if `link == nil` → `connectIfPossible(replayingInitialize: true)`. The thread is stopped and joined in `run` before `session.close()`.
- Rename `answeredAlone` to `needsAnnounce`: set when the bridge answers a request alone or loses a link; cleared and the two `list_changed` notifications written when a connect succeeds (by a request or by `poll()`).
- Handshake: `Link` gains `handshake: Mutex<Handshake?>` + semaphore, `enum Handshake { case accepted, refused(String) }`. The reader thread, on the replay answer, records `.refused(message)` when the line has `error.code == -32001`, else `.accepted`, and still never forwards it. `connectIfPossible(replayingInitialize: true)` waits up to `handshakeTimeout` for it: `.refused` closes the link, stores `refusal = message`, returns with `link == nil`; timeout proceeds as today.
- `answerAlone` and `initialize` instructions use `refusal ?? MCPBridge.noAppSentence`; a successful connect clears `refusal`. A `tools/call` while refused returns `MCPBridge.toolError(refusal)`.
- `MCPBridge.refusedSentence` is not needed: the sentence is the listener's `busySentence` as received.

Tests (`BridgeTests`; extend `Harness` with `retryInterval: Duration = .milliseconds(50)`):
- `appStartingLaterIsAnnouncedWithoutAnotherRequest`: replaces the final request in `appStartingLaterIsPickedUp`'s flow: initialize + initialized with no app, then start the listener, send nothing, and assert within 10 s the client receives `notifications/tools/list_changed` then `notifications/resources/list_changed`, and `seen` holds `["initialize", "notifications/initialized"]` (the replay). Keep a variant that sends `tools/list` afterwards and gets the app's answer.
- `appRestartIsAnnouncedAgain`: connected bridge, `app.stop()` (pending request, if any, answered "MetalCreator closed the connection before answering."), a new listener on the same path; assert a second pair of `list_changed` arrives with no client request.
- `anIdleBridgeDoesNotHoldTheApp`: the bridge started, client silent for 500 ms: a raw client connecting to the app is served and `states` never saw `true` from the bridge.
- `aSecondClientIsToldTheAppIsBusy`: a raw client holds the app; the bridge's client sends `initialize`: its `instructions` equal `MCPListener.busySentence`; a `tools/call` returns `isError` with that text; `tools/list` is empty; after the raw client closes, within 10 s the client receives `list_changed` and a `tools/list` is forwarded to the app.
- `noWatcherWorkBeforeInitialize`: no listener, no `initialize`: nothing is written to stdout over 300 ms.
- `endOfInputStopsTheWatcher`: `harness.finish()` returns 0 within 5 s while the app is down (existing helper).
- Existing tests `bridgeCopiesBothWays`, `appClosingMidRequestAnswersEachPendingRequest`, `endOfInputWaitsForAPendingReply` keep passing unchanged (adjust only for the missing start-up connect).

### A3. Menu: turn off from the failed and in-use states (item 3)

- `MCPService`: `@ObservationIgnored private var switchedOffThisSession = false`; `isOn` becomes `(preference.allowsAIConnections || launchFlag) && !switchedOffThisSession`; `public func turnOff()`: `preference.allowsAIConnections = false; switchedOffThisSession = true; stop()`; `setOn(true)` and `menuChosen` retries clear `switchedOffThisSession`. `public var offersTurnOff: Bool { retries }`; `public static let turnOffTitle = "Turn Off AI Connections"`.
- `AppCommands.aiConnectionsItem`: when `service.offersTurnOff`, a `Button(MCPService.turnOffTitle) { service.turnOff() }` follows the toggle.

Tests (`MCPServiceTests`): `turnOffFromInUseStopsAndForgetsTheChoice` (second window `.inUse`; `turnOff()`; `state == .off`, `!isOn`, preference false, the first window's listener untouched); `turnOffFromFailed` (too-long path as the existing failed test: `.off`, `menuTitle == "Allow AI Connections"`); `turnOffWinsOverTheLaunchFlag` (`launchFlag: true`, `.failed`; `turnOff()` → `!isOn`, `state == .off`; `menuChosen(true)` turns it back on); `offersTurnOffOnlyWhenRetrying` (`offersTurnOff == retries` across off/listening/inUse/failed).

### A4. Docs and human checks (Track A)

- `docs/mcp.md`: "Turning it on": the bridge connects when the client first asks and keeps trying in the background (every second), announcing the tools when the app appears or comes back; "If another client is connected, a second one is told 'MetalCreator is already connected to another AI client…' and connects by itself when the first leaves"; the menu's "Turn Off AI Connections" in the error states.
- `docs/verification/human-checks.md`, group MCP, new unchecked items (continue the numbering after the last MCP item):
  - **MCP-8 App opens after the client.** Quit MetalCreator, start Claude Code with the bridge configured (`/mcp` shows no tools), then launch MetalCreator with Allow AI Connections on: without `/mcp` reconnect, within a few seconds Claude's tool list fills in and the "AI connected" chip appears when it first calls a tool.
  - **MCP-9 App restarts under a connected client.** With Claude connected, quit and relaunch MetalCreator: Claude's next call works without reconnecting.
  - **MCP-10 Second client.** With Claude Code connected, start a second client (the Claude desktop app or `claude` in another terminal): it shows "MetalCreator is already connected to another AI client…" within about two seconds, not a 30 s timeout; quit the first and the second's tools appear without a manual reconnect.
  - **MCP-11 Switch off from an error state.** Run two MetalCreator windows (or a second instance): the second's menu reads "AI Connections: in use by another window" with "Turn Off AI Connections" under it; choosing it clears the state and the item reads "Allow AI Connections"; the first window's connection is unaffected.

---

## Track B

Edit safety: item 4. Files: `Sources/CreatorApp/FilePanelActivity.swift` (new), `Sources/CreatorApp/AppModel.swift`, `AppModel+Files.swift`, `AppModel+Images.swift`, `AppModel+MeshFiles.swift`, `AppModel+Export.swift`, `Sources/CreatorApp/MCP/AppDocumentSession.swift`; tests `Tests/CreatorAppTests/MCP/AppDocumentSessionTests.swift`.

### B1. Counting open panels

- `@MainActor @Observable public final class FilePanelActivity { public private(set) var open = 0; public var isOpen: Bool { open > 0 }; func begin(); func end() }`.
- `struct ActivityFilePicker: FilePicker { let base: any FilePicker; let activity: FilePanelActivity }`: both methods `activity.begin(); defer { activity.end() }; return try await base...` (so a thrown or cancelled panel releases it).
- `AppModel`: `public let filePanels = FilePanelActivity()` and `func tracked(_ picker: any FilePicker) -> any FilePicker`. Every entry point that takes a `picker` starts with `let picker = tracked(picker)`: `openDocument(using:)`, `saveDocument(using:)`, `saveDocumentAs(using:)`, `chooseAndOpen(using:)` (Files), the three image methods (Images), the two mesh-file methods and the import one (MeshFiles), and the export destination (Export). `ThemeEditorModel` is left out on purpose (R5).

### B2. The refusals

`AppDocumentSession.askRefusal()` becomes, in this order (alert rule first, unchanged; the sketch, pick, dimension, canvas and scrubbing sentences unchanged):

1. `model.alert != nil || model.closeRequest != .idle` → "MetalCreator is asking you something. Answer it, then try again."
2. `model.exportRun != nil` → "MetalCreator is exporting a file. Wait for it to finish, or cancel it in the export window, then try again."
3. `model.filePanels.isOpen` → "MetalCreator is showing a file panel. Choose a file or cancel the panel, then try again."
4. `model.document.isHoldingResults` → "MetalCreator is checking a change in the window. Try again in a moment."
5. then sketch, pick, model dimension, canvas interaction, scrubbing as now.

`AppDocumentSession.export` must not refuse itself on its own sheet: its check runs before `exportReturningWarnings` sets `exportRun`, and requests are served one at a time, so no change is needed; a test pins it.

### B3. Tests (`AppDocumentSessionTests`, names exact)

- `exportSheetRefusesEdits`: with `model.exportHold` suspending a streamed export so `exportRun != nil`, `add_node` through the session returns `.refused` with the export sentence; undo, redo, `newDocument`, `open`, `save`, `setFile` also refuse; after the export is cancelled the same `add_node` succeeds.
- `filePanelRefusesEditsAndFileTools`: a `GatedFilePicker` (test double whose `chooseFileToOpen` suspends on a continuation) is passed to `model.openDocument(using:)` in a `Task`; while suspended `editRefusal()` is the file-panel sentence and `perform` through `EditOutcome.run` returns it; after resuming with `nil` it is `nil` again.
- `aPickerThatThrowsReleasesThePanel`: the gated picker throws `FileDialogError.busy`; `model.filePanels.isOpen == false` afterwards and an edit works.
- `everyPickerEntryPointIsTracked`: for each of the model's picker-taking methods (open, save as, choose image, relink image, choose mesh, relink mesh, export destination), start it with the gated picker and assert `filePanels.isOpen` while it waits.
- `heldResultsRefuseEdits`: `model.document.holdResults()` → `editRefusal()` is the held sentence; `releaseResults()` → `nil`.
- `refusalOrderIsStable`: alert + export + panel together give the alert sentence; export + panel give the export sentence; panel + held give the panel sentence.
- `aClientsOwnExportIsNotRefusedByItself`: `export("stl", ...)` on a one-box document succeeds (the existing export tests stay green).
- `themeEditorPanelDoesNotRefuse`: a `ThemeEditorModel` import with a gated picker leaves `editRefusal() == nil`.

### B4. Docs and human checks (Track B)

- `docs/mcp.md` Rules ▸ Modes: add "the export window is open, a file open/save panel is up, or the app is checking a change" to the refusal list.
- `docs/verification/human-checks.md`, group MCP: **MCP-12 Refused behind the export window and file panels.** Start an export (File ▸ Export… and keep the destination panel open, then confirm into a slow export if available) and ask Claude to add a node while the panel and then the sheet are up: it is refused with the matching sentence each time; after dismissing, the same request works. Repeat with File ▸ Open… and Choose Image….

---

## Track C

Reporting: items 6, 7, 8. Files: new `Sources/CreatorMCP/Tools/SolidFacts.swift`; `Session/DocumentModelSession.swift` (`ValueSummary`), `Tools/ReadTools.swift`, `Tools/EditOutcome.swift`, `Tools/EditTools.swift`, `Sources/CreatorGraph/UndoName.swift`; tests in `Tests/CreatorMCPTests` (`ReadToolTests`, `EditToolTests`, new `SolidFactsTests`, `BatchNameTests`) and `Tests/CreatorGraphTests/UndoNameTests.swift`.

### C1. Solid facts (item 6)

```swift
public struct SolidFacts: Equatable, Sendable {
    public var faces: Int, edges: Int
    public var min: Vector3, max: Vector3
    public init(_ solid: Solid)                 // topology.faces.count, topology.edges.count, bounds
    public var text: String                     // "solid: 6 faces, 12 edges, bounds (0, 0, 0) to (60, 40, 5) mm"
    @MainActor var json: JSONValue              // {faces, edges, bounds_min:[x,y,z], bounds_max:[x,y,z]}
}
```

- Numbers rounded with `ValueSummary.format` (4 decimals); "1 face", "1 edge" singular; an empty bounding box (min > max) prints "no bounds".
- `ValueSummary.singular`: `.solid(let solid)` returns `SolidFacts(solid).text`. A list or tree of solids is unchanged ("3 solids", "tree of 4 solids").
- `ReadTools.nodeJSON` outputs entries gain `solids` (first 20 `SolidFacts.json` of the output value's solid items, flattened in order) and `solids_total` when more than 20; omitted when the output has none. `outputSummaries(of:_:)` becomes `static` internal (not private) so `EditOutcome` reuses it.
- `EditOutcome.report`: each `changed` entry gets `"outputs": <outputSummaries>` when that map is non-empty.

Tests:
- `SolidFactsTests.textPluralsAndRounding`: a hand-built `Solid` (FakeKernel box 60 × 40 × 5) gives exactly `solid: 6 faces, 12 edges, bounds (0, 0, 0) to (60, 40, 5) mm` (read the actual counts FakeKernel produces and pin them); a one-face fake gives "1 face"; bounds `0.123456` print `0.1235`.
- `ReadToolTests.nodeShowsValuesWiresAndSummaries`: the Extrude output summary is the string above (fixture's real size), `solids` has one entry with `faces`, `edges`, `bounds_min`, `bounds_max` that match; `ReadToolTests.documentOutputsCarryFacts`: `get_document` node `outputs.solid` equals the same string.
- `ReadToolTests.listOfSolidsKeepsTheCountAndCapsFacts`: 25 solids from a pattern give summary "25 solids", `solids.count == 20`, `solids_total == 25`.
- `EditToolTests.changedEntriesCarryOutputs`: `set_inputs` Extrude distance → the `changed` entry for Extrude has `outputs.solid` with the new bounds; a state-only change on a node with no outputs has no `outputs` key.
- `ReadToolTests` existing assertions that expected "solid" are updated to the new string.

### C2. Set versus default (item 7)

In `ReadTools.nodeJSON` inputs: replace the `if/else if` with

```swift
let stored = node.inputValues[spec.name]
if wired { fields["wired_from"] = ...; fields["source"] = "wired" }
else if let stored { fields["value"] = constantJSON(stored); fields["source"] = "set" }
else if let value = spec.defaultValue { fields["value"] = constantJSON(value); fields["source"] = "default" }
else { fields["source"] = "unset" }
```

`default` stays as today. Tests (`ReadToolTests`): `getNodeSourceDistinguishesSetFromDefault`: the fixture's Extrude `distance` before any edit is `"default"` (value 10); after `set_inputs distance = 10` (equal to the default) it is `"set"` with `value` 10; after `set_inputs distance = null` it is `"default"` again; `profile` is `"wired"`; a socket with neither stored value nor default (an optional input) is `"unset"` and has no `value`. `describe_node_type` is untouched.

### C3. A batch's own step name (item 8)

- `UndoName` (CreatorGraph): `public static let build = "Build"`, `rewire = "Rewire"`, `rearrange = "Rearrange"`, `cleanUp = "Clean Up"`, `editGraph = "Edit Graph"`, and `public static let clientBatchNames = [build, rewire, rearrange, cleanUp, delete, editGraph]` (`delete` exists). The existing `UndoNameTests` that reject digits and typed text cover the new constants; add them to its list.
- `batch` schema gains `step_name` (string, "One of Build, Rewire, Rearrange, Clean Up, Delete, Edit Graph; omit to let MetalCreator choose").
- `EditTools.batchTool`: validate `step_name` first (not a string, or not in the list: refuse "The step name must be one of Build, Rewire, Rearrange, Clean Up, Delete or Edit Graph."); a missing one uses `EditTools.batchName(for plans: [Plan]) -> String`: exactly one operation → that plan's own name; else by the commands (any `.addNode` → `UndoName.build`; all `.removeNode` → `UndoName.delete`; all `.connect`/`.disconnect` → `UndoName.rewire`; all `.move` → `UndoName.rearrange`; otherwise `UndoName.editGraph`). The result's `step` is that name, and `EditOutcome.run(name:)` is unchanged.

Tests (`BatchNameTests`): `batchOfAddsAndConnectsIsBuild` (the MCP-2 shape: rectangle, extrude, connect → `document.undoName == "Build"`, result `step == "Build"`); `singleOperationBatchKeepsItsOwnName` ("Add Revolve"); `connectOnlyBatchIsRewire`; `moveOnlyBatchIsRearrange`; `removeOnlyBatchIsDelete`; `mixedWithoutAddIsEditGraph` (set_inputs + rename); `explicitStepNameWins` (`step_name: "Clean Up"` on an add-only batch → "Clean Up"); `unknownStepNameIsRefusedAndChangesNothing` (`"Make a plate"` → `isError`, the sentence above, graph unchanged, no undo entry); `nonStringStepNameIsRefused`; `batchUndoRedoNamesMatch` (`undo` tool result `step` equals the name and `redoName` matches). The existing batch tests that expected the first edit's name are updated.

### C4. Docs and human checks (Track C)

- `docs/mcp.md` Tools: get_node/get_document paragraphs (solid facts; `source`), batch (`step_name` list and the default naming), edit results (`outputs` per changed node).
- Human check **MCP-13 Names and facts.** Ask Claude to build the plate with holes in one batch: the bar and Edit menu read "Undo Build" (not "Undo Add Rectangle"); ask "how big is the plate?" and Claude answers from the Extrude's face count and bounds without a second tool.

---

## Track D

Clean-up: items 9 and 10, then the docs for the whole plan. Files: new `Sources/CreatorGraph/GraphError+Message.swift`, `SocketLabel.swift`, `CanvasMetrics.swift`; delete `Sources/CreatorEditor/GraphError+Message.swift`; edit `Sources/CreatorEditor/InspectorLabel.swift`, `NodeLayout.swift`, `Sources/CreatorMCP/Tools/EditOutcome.swift`, `EditTools+Planning.swift`, `ValueCoercion.swift`, `Session/DocumentModelSession.swift`, `scripts/package-linux.sh`, `scripts/linux-test.sh`; tests `Tests/CreatorGraphTests`, `Tests/CreatorEditorTests/FormattingTests.swift`, `Tests/CreatorMCPTests/ValueCoercionTests.swift`, `Tests/CreatorAppTests/PackagingScriptTests.swift`.

### D1. One definition each (item 9)

- `GraphError.message` (public, identical switch: `.invalidConnection(let problem)` → `problem.message`, `.nodeNotFound` → "That node no longer exists.", `.duplicateNode` → "That node already exists.", `.linkNotFound` → "That wire no longer exists.", `.parameterNotFound` → "That parameter no longer exists.", `.invalidValue(let m)` → `m`) moves to `CreatorGraph/GraphError+Message.swift` beside `ConnectionProblem+Message.swift`; the editor's file is deleted; `EditOutcome.message(_:)` is deleted and its callers (`EditOutcome.run`, `EditTools.commit`) use `error.message`. Nothing else changes for the editor and app, which already import `CreatorGraph`.
- `public enum SocketLabel { public static func text(for socket: SocketName) -> String }` in `CreatorGraph/SocketLabel.swift`, with the body of today's `InspectorLabel.text` ("cornerRadius" → "Corner radius"). `InspectorLabel.text(for:)` becomes a one-line forward (keeps its many callers); `ValueCoercion.label(for:)` is removed and its callers in `EditTools+Planning.swift` and `ValueCoercion.swift` use `SocketLabel.text(for:)`.
- `public enum CanvasMetrics { public static let nodeWidth = 224.0 }` in `CreatorGraph/CanvasMetrics.swift`; `NodeLayout.width` is `CanvasMetrics.nodeWidth`; `DocumentModelSession.nodeWidth` is removed and `freePosition` uses `CanvasMetrics.nodeWidth` (the 40 pt `nodeGap` stays there with a comment that it is the MCP's own spacing).
- Before finishing, `grep -rn "224" Sources/CreatorMCP` and `grep -rn "no longer exists" Sources` for any further copy.

Tests:
- `CreatorGraphTests.GraphErrorMessageTests.everyCaseHasItsSentence` (each case's exact text above, and `.invalidConnection` equals the problem's message).
- `CreatorGraphTests.SocketLabelTests.splitsCamelCase` (`cornerRadius` → "Corner radius", `width` → "Width", `holeCountX` → "Hole count x", `x` → "X", empty → "").
- `CreatorEditorTests.FormattingTests`: the existing three `InspectorLabel` assertions stay, plus `inspectorLabelEqualsSocketLabel` over every input name of the built-in registry; `NodeLayoutTests.widthIsTheSharedMetric` (`NodeLayout.width == CanvasMetrics.nodeWidth == 224`).
- `CreatorMCPTests.ValueCoercionTests`: the label tests move to call `SocketLabel.text(for:)`; add `refusalsUseTheInspectorLabels` (a number out of range says "Distance must be…" using the shared label) so the MCP's wording cannot drift from the inspector's.
- `CreatorMCPTests.PlacementTests.freePositionUsesTheNodeWidth`: with one node at x = 100 the next free position's x is `100 + CanvasMetrics.nodeWidth + 40`.

### D2. Scan the bridge on Linux (item 10)

`scripts/package-linux.sh`, "Copying the non-system libraries it links" step: replace the single `ldd "$BINARY"` block with

```sh
for EXE in "$BINARY" "$BRIDGE"; do
    ldd "$EXE" > "$WORK/ldd-$(basename "$EXE").txt"
    grep -q "not found" "$WORK/ldd-$(basename "$EXE").txt" && fail "ldd can't find a library for $(basename "$EXE"): ..."
    # the same copy-and-patchelf loop (cp -L is idempotent, so a library both link is copied once)
done
```

then, after the loop, `ldd "$FOLDER/metalcreator-mcp"` must show no "not found" (its rpath is `$ORIGIN/lib`, set earlier) else `fail "the packaged metalcreator-mcp can't find a library"`. The printed library count is of distinct files. `scripts/linux-test.sh`'s clean-Ubuntu tarball step adds, beside `./MetalCreator --version`: `printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"verify","version":"1"}}}' | ./metalcreator-mcp --socket /nonexistent/x.sock | head -n 1 | grep -q "isn't running"` and an `ldd metalcreator-mcp | grep -q "not found"` negative check; the AppImage step (`--appimage-extract-and-run` of the app) is unchanged since it is packed from the tarball's tree. The Docker suite is not run here (CI covers it); this is checked by `PackagingScriptTests`.

Tests (`PackagingScriptTests`, macOS-side text checks like its neighbours): `linuxPackageScansTheBridge` (`package-linux.sh` contains `for EXE in "$BINARY" "$BRIDGE"; do` and `ldd "$FOLDER/metalcreator-mcp"`); `linuxCleanCheckRunsTheBridge` (`linux-test.sh` contains `metalcreator-mcp --socket /nonexistent/x.sock`); `windowsPackageScansTheBridge` (`package-windows.ps1` contains the `$queue.Enqueue((Join-Path $folder 'metalcreator-mcp.exe'))` line, pinning what already holds).

### D3. Docs for the whole plan

- `docs/mcp.md`: all the Track A to C edits (check the page reads as one), and a line in "The socket" that the bridge holds no connection until its client's first request.
- `CLAUDE.md`, the MCP paragraph (`MCP server, MCP-1 …`): append a sentence "MCP-1b (plan `docs/superpowers/plans/2026-11-13-mcp-1b-followups.md`) code is done; its human checks (MCP-8 to MCP-13) are pending:" followed by the new facts in one dense run: the bridge connects at the client's first request and a watcher retries every second and announces `list_changed` when the app appears or returns; a second client gets error `-32001` "MetalCreator is already connected to another AI client…" (the listener waits a 1 s grace for the slot); "Turn Off AI Connections" in the `.inUse`/`.failed` states; edits refused while the export sheet, a file panel (`FilePanelActivity`, `AppModel.tracked(_:)`) or held results; solid summaries carry faces, edges and bounds, `get_node` inputs carry `source`; `batch`'s fixed `step_name` list (`UndoName.clientBatchNames`); `GraphError.message`, `SocketLabel` and `CanvasMetrics.nodeWidth` live in `CreatorGraph`; `package-linux.sh` scans the bridge. In the same paragraph change "a client's edits are refused while sketching, picking, …" to include the new refusals.
- `docs/superpowers/specs/2026-11-08-mcp-server-design.md`, Errata: add

  `- 2026-11-13 (MCP-1b follow-ups): the bridge connects to the app at its client's first request, not at start, and retries in the background (R1, R2 of plan 2026-11-13-mcp-1b-followups); the listener refuses a second client with JSON-RPC error -32001 and a sentence; the menu can turn the server off from the failed and in-use states; edits are also refused during the export sheet, a file panel and held results (§Modes amended); output summaries of a solid read "solid: N faces, M edges, bounds (…) to (…) mm"; get_node inputs say whether a value is wired, set, default or unset; batch accepts a step_name from a fixed list (no free text, per the undo-name rules) and otherwise names itself from its contents; GraphError.message, the socket label rule and the node width are shared from CreatorGraph.`

- Human checks (all in group MCP of `docs/verification/human-checks.md`, unchecked): MCP-8 to MCP-13 as written in A4, B4 and C4. MCP-7's in-flight case and Windows `AF_UNIX` on a real machine stay out of scope and stay listed as not seen.

### D4. Final verification

- `swift build`; `swift test --filter CreatorMCPTests`; `swift test --filter CreatorGraphTests`; `swift test --filter CreatorEditorTests`; the MCP suites of `CreatorAppTests` and `PackagingScriptTests`; then the full `swift test` once (13 "Test run with" lines, no "recorded an issue" or "failed after"); `swiftlint lint --strict` zero violations.
- Read each diff against this plan's sentences character for character (the refusal and busy sentences are asserted by tests and quoted in docs).
- Do not push, open a PR or merge.
