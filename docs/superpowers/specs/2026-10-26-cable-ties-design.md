# Cable ties: bundling wires in the graph editor

Status: approved in conversation 2026-10-26; this document is for the user's review.

## 1. Purpose

Big graphs turn into spaghetti. The user wants MetalCreator to "maintain a level of cleanliness and avoid the spaghetti look
where we can", inspired by Trellis's bundled, bouncy wires (Dan Fessler, x.com/DanFessler/status/2113892726869737800).

What the user decided (2026-10-26):

- **Manual, not automatic.** The user selects wires and presses a shortcut; a cable tie appears around them. No automatic
  bundling ("to avoid over-optimization").
- **A tie gathers.** It is a shared, draggable waypoint: the tied wires run through it side by side and fan out after it.
- **Selecting wires:** a click on a wire; ⌥-drag on empty canvas box-selects wires only. A plain box still selects nodes.
- **Shortcut ⌘⇧T.**
- **Motion:** wires go slack while things move and pull taut when they stop. No lag: the ends track sockets and ties
  exactly. At rest every wire is the taut curve. No sag at rest.
- **Tie editing:** the defaults in §4.4 were accepted as proposed.
- **Storage:** ties are canvas furniture in the graph (approach A), with a file format bump to 9.

Success: a user can take a tangle of wires, tie them into a few tidy bundles in seconds, drag the bundles out of the way, and
the file reopens exactly as they left it.

Out of scope: automatic bundling or routing, sag at rest, wire colours or labels, reroute nodes, ties in the viewport.

## 2. Context

- Graph model: `Graph` (`Sources/CreatorGraph/Graph.swift`) holds `nodes`, `links: [Link]`, `parameters`, `stickies`, `frames`.
  `Link{from: Endpoint, to: Endpoint}`. An input takes at most one link, so **a wire is identified by its input endpoint
  (`Link.to`)**. Wires have no other id.
- Comments (stickies and frames) are the precedent for editor furniture stored in the graph (selection-groups-comments spec §7):
  optional keys written only when non-empty, plain non-evaluating commands, remapped on paste.
- Wires are drawn by `CanvasLayers.wires` as one cubic per link (`WireGeometry`, `WireShape`, `WireView`), coloured by the
  source socket type and culled against `drawnCanvasRect`. They are not hit-tested or selectable today.
- Selection is `CanvasSelection{nodes, comments}`: view state, never saved or undone. Box modes: none replaces, ⇧ adds, ⌘
  toggles (selection spec §3, Errata A). ⌥ on a node or comment drag duplicates. ⌥ on empty canvas currently does a plain box.
- Stored coordinates are left-to-right flow. `CanvasFlow` converts to display (the vertical dock is a transpose).
- MetalUI provides `TimelineView(.animation)` and the environment value `accessibilityReduceMotion`. Neither is used by
  MetalCreator yet.

## 3. Data model and file format

### 3.1 CableTie

```swift
public struct TieID: Hashable, Codable, Sendable { public let raw: UUID }

public struct CableTie: Hashable, Codable, Sendable, Identifiable {
    public var id: TieID
    public var position: Vector2        // stored (flow) coordinates, like Node.position
    public var wires: Set<Endpoint>     // each wire named by its input endpoint, Link.to
}
```

`Graph.ties: [TieID: CableTie]`, beside `stickies` and `frames`. A group definition's graph has its own ties, because
`GroupDefinition.graph` is a full `Graph`.

**Invariants**, which `Graph.apply` keeps and decoding repairs:

- (I1) Every endpoint in `wires` is the `to` of an existing link.
- (I2) A tie holds at least two wires. A tie that would hold fewer is removed.
- A wire may be held by any number of ties.

### 3.2 Commands

New `GraphCommand` cases:

- `setTie(CableTie)` adds or replaces a tie. Its inverse is the previous tie, or `removeTie`.
- `removeTie(TieID)`: its inverse is `setTie(old)`.

Like the comment commands, both have `touchedNodes` empty and `affectsResults` false. Both work under `.inDefinition` and `.at`.
Undo names: "Tie Wires", "Add to Tie", "Move Tie", "Remove Tie", "Untie Wire".

**Wires leaving ties automatically.** These commands now also strip affected wires from ties, inside the same command, and
their inverses restore the ties exactly:

- `removeNode`: every wire into or out of the node.
- `disconnect`: that wire.
- `connect` onto an input that already had a link: the replaced wire. A new wire is never tied implicitly.

After stripping, (I2) removes any tie left with fewer than two wires. `restoreNode` and `restoreLinks` gain the tie snapshot
they need, or the inverse is a `batch` with `setTie` commands. The plan chooses which, keeping one undo step per user action.

### 3.3 File format 9

- `GraphFile.currentFormatVersion` becomes 9. The history note in `GraphFile.swift` says 9 added `ties`. Older apps refuse
  format-9 files through their existing newer-version check, so ties cannot be lost by an older app re-saving the file.
- The `ties` key is written only when non-empty, sorted by id, with each tie's `wires` sorted. This keeps the output
  deterministic.
- Decoding format 8 or older gives no ties. Decoding format 9 drops wires that break (I1), then ties that break (I2). It
  tolerates duplicate ids the way stickies do.

### 3.4 Clipboard, paste, duplicate

`NodeClipboard` gains `ties`. `clipboard(of:)` includes a tie only if every wire it holds is copied: both ends of each link are
in the selection. `insert` gives the tie a fresh id, remaps its endpoints to the new node ids, and offsets its position like
the pasted nodes. Duplicating with ⌥-drag works the same way.

## 4. Interaction

### 4.1 Selection

`CanvasSelection` gains two sets, both view state, never saved and never undone:

- `wires: Set<Endpoint>`, keyed by input endpoint.
- `ties: Set<TieID>`.

- **Wire hit-test.** `hitTest` gains `.wire(Endpoint)` and `.tie(TieID)`. A point within 5 pt (display) of a wire's drawn
  route hits it. A point within a tie's band hits the tie. Priority, highest first: socket, tie, node, note, wire, frame,
  resize, empty. The wire is tested against its taut route (§5), never against the animated shape.
- **Click:**
  - a click on a wire or tie selects it, replacing the selection;
  - ⇧ adds and ⌘ toggles (⌘ wins), as for nodes;
  - a click on empty canvas clears everything, wires and ties included.
- **⌥-drag on empty canvas** draws a box that selects only wires: those whose taut route crosses or lies inside the box. The
  modifiers held at the start fix the mode: ⌥ alone replaces the wire selection, ⌥⇧ adds, ⌥⌘ toggles. Nodes, comments and
  ties keep their selection. Esc restores the selection the drag began with.
- **A plain box** (no ⌥) selects nodes and comments as now, plus **ties** whose band lies inside the box. It never selects
  wires.
- Selected wires draw with a highlight (wider, in the theme's selection colour). Selected ties draw their band in the
  selection colour.

### 4.2 ⌘⇧T: tie

`GraphKeyBindings.commandChord` maps ⌘⇧T to the new `GraphKeyCommand.tieWires`. The check uses MetalUI's `.primary`, so the
shortcut is Ctrl+Shift+T on Linux and Windows; ⌥ is Alt there. It runs only while the panel is visible and
no interaction is under way, like the other selection commands.

- **No tie selected, two or more wires selected:** it creates a tie holding them, named "Tie Wires".
  - **Position:** if the wires were box-selected, the centre of the points where their taut routes lie inside the box.
    Otherwise, the centre of the points where they were clicked, which the selection remembers in memory only.
  - After creating it, the selection becomes just the new tie.
- **Exactly one tie selected and one or more wires selected:** it adds those wires to that tie, named "Add to Tie".
- **Anything else** (fewer than two wires and no tie, or two or more ties): the existing refusal shake.

### 4.3 Moving ties

Dragging a tie moves it, coalesced into one undo step ("Move Tie") as node moves are. A selection holding ties together with
nodes and comments moves all of them together. Ties are also snapped and nudged like nodes, wherever the editor already does
that for nodes.

### 4.4 Editing ties (defaults accepted)

- **Delete** with ties selected removes them ("Remove Tie"). The wires go back to their plain routes. Delete with only wires
  selected does nothing; wires are still removed by dragging their input end off, as today.
- **⌥-click on a wire within a tie's band** removes that wire from that tie ("Untie Wire"). (I2) applies.
- A wire can pass through several ties.
- Deleting a node or a wire takes its wires out of their ties (§3.2).
- Everything can be undone.

### 4.5 Groups

Ties live in whichever graph level they were made at: the top level or inside a definition. They are edited there through
`.at` and `.inDefinition`. Grouping nodes moves a tie into the new definition only if all of its wires move with them.
Otherwise the wires that cross the group boundary leave the tie, and (I2) applies. Ungrouping moves the definition's ties back
out, remapped.

## 5. Drawing

### 5.1 Route

A wire's **taut route** is a chain of cubic pieces:

    source socket → tie₁ lane → tie₂ lane → … → target socket

- **Tie order:** the wire's ties sorted by stored flow position, `position.x`, ties by id. In the vertical dock this is
  top-to-bottom on screen, because display is the transpose.
- **Lane:** at a tie, the wire passes through its lane point. Each piece leaves its start and enters its end along the flow
  direction, with the same reach rule as `WireGeometry`: `max(40, |along| × 0.5)`. So the pieces join tangent-continuous
  (G1) at every lane, and an untied wire's route is exactly today's single cubic.
- **Lanes:** a tie with n wires puts them in lanes 4 pt apart, centred on `position`, across the flow. They are ordered by
  their target socket's display position across the flow, ties broken by endpoint, to cut down crossings after the fan-out.
- **The band** is a rounded rectangle across all the lanes, 6 pt along the flow, extending 3 pt beyond the outer lanes. It
  uses the theme's `glassStroke` colour and is drawn above the wires and below the nodes.

`WireRoute` (pure, in `CreatorEditor`) computes the routes, lanes and band rectangles from the graph, the anchors and the
flow. Culling uses each route's bounds. A tie is culled by its band.

**Draw order** becomes: frames → wires → tie bands → notes → nodes → ghosts → dragged wire → box.

### 5.2 Motion

The goal is slack while moving, taut at rest, and no lag.

- **Pinned points.** The pinned points of a route are its socket ends and lane points. They are drawn exactly where they
  are at every frame.
- **Spring state.** Each piece's two control points are offset from their taut positions by a spring state: an offset and
  a velocity per control point. The drawn control point is the taut control point plus the offset.
- **What excites it.** When a piece's pinned ends move by Δ in a frame, its control points' targets jump by Δ but their
  drawn positions lag. The offset grows by −Δ times a slack factor below 1, so the piece bows behind the motion like a cable.
  A damped spring then pulls the offset back to zero.
- **Constants**, tuned by eye during human checks:
  - critically damped or slightly under (damping ratio about 0.8);
  - settles within about 0.3 s;
  - the offset is capped at 40% of the piece's length, so it never folds over.
- **At rest** the offset is exactly zero. A tolerance snaps tiny residues to zero, and then the drawn route is the taut route,
  bit for bit.
- **The tick.** The canvas wraps the wire layer in `TimelineView(.animation)` only while some spring state is non-zero.
  Otherwise it draws statically and costs nothing per frame. The step function is pure: `(state, Δ of pinned points, dt)` to
  a new state. It takes `dt` from an injected clock, so tests step it frame by frame.
- **Reduce Motion.** When MetalUI's `accessibilityReduceMotion` is true, no spring state is ever created: wires are always
  taut.
- **Hit-testing, culling and saving** use the taut route only. Motion is never saved.

## 6. Testing

- **CreatorGraph:**
  - `setTie` and `removeTie` and their inverses;
  - `removeNode`, `disconnect` and a replacing `connect` strip ties, (I2) removes small ties, and undo restores ties exactly;
  - `.inDefinition` ties;
  - format 9 round-trip, deterministic output, decoding repairs (I1) and (I2), format 8 decodes to no ties, and the current
    reader's version check refuses format 10;
  - clipboard and paste remapping.
- **CreatorEditor:**
  - the hit-test priority table;
  - click, ⇧ and ⌘ on wires and ties;
  - ⌥-box modes and Esc;
  - a plain box picks up ties;
  - ⌘⇧T: create, add, refuse, and the position rule;
  - Delete on ties;
  - ⌥-click untie;
  - moving ties alone and with nodes, as one undo step;
  - group and ungroup with ties;
  - the vertical dock.
- **WireRoute:**
  - an untied route equals `WireGeometry`;
  - routes through one and several ties, with tie order by flow;
  - G1 continuity at lanes;
  - lane spacing and order;
  - band rectangles;
  - culling bounds.
- **Spring:**
  - pinned points are exact on every step (no lag);
  - a moving end produces slack opposite the motion;
  - it settles to exactly zero offset within the time budget;
  - the cap holds;
  - Reduce Motion means no state;
  - the timeline is active only while state is non-zero.
- **Human checks**, a new group in `docs/verification/human-checks.md`: the feel of slack and settling; the band's look in
  dark and light themes; ⌘⇧T flow end to end; Reduce Motion; the vertical dock; a busy graph stays smooth when dragging a tie
  holding about 20 wires.

## 7. Spec errata to add when this lands

- Vertical slice §6.2 (graph panel input): wires can be clicked; ⌥-drag on empty canvas selects wires; ⌘⇧T ties.
- Selection-groups-comments §3: `CanvasSelection` gains wires and ties. §7: draw order gains tie bands; hit-test order gains
  tie and wire.
- The format-version history in `GraphFile.swift` gains format 9.
