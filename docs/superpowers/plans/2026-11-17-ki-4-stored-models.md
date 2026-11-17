# KI-4: KiCad board import — models stored in the board — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A footprint model named `kicad-embed://<name>` is found in the board's `(embedded_files …)` (or the footprint's own), decoded
(base64, then one zstd frame) and read as any other model of its format, so a KiCad 9+ board that carries its models inside reads complete
on any machine.

**Architecture:** `CreatorPCB/Embedded/` gains `Base64` and a portable `ZstdDecoder` (RFC 8878, decoding only) with `XXH64` for the frame
checksum; the board reader keeps `embedded_files` entries of type `model` as raw base64 text; the node's `BoardComponents` resolves
`.embedded(name:)` to bytes and hands them to the KI-2/KI-3 pipeline by the name's format.

**Tech Stack:** Swift 6.4, Swift Testing; fixtures made with the `zstd` 1.5 command line (Homebrew) and checked in as base64 strings.

**Spec:** `docs/superpowers/specs/2026-11-15-kicad-import-design.md` (§Components: Models stored in the board; §Limits; KI-4). Facts:
`docs/superpowers/specs/2026-11-16-kicad-format-facts.md` §2.

## Global Constraints

- Worktree `/Users/maxburger/Developer/kicad-import/MetalCreator-ki4`, branch `kicad-ki-4` (stacked on `kicad-ki-3`, rebased onto it before Task 3). Never touch MetalUI.
- Portable Swift only (no libzstd, no Compression framework, no CryptoKit); `CreatorPCB` depends on `CreatorGeometry` only.
- Untrusted input: the frame's stated content size is checked against the model's limit (STEP/IGES 256 MB, VRML/X3D 64 MB, IDF 16 MB)
  before allocating; with no stated size, output stops at the limit with a refusal; window size at most 256 MB; every table and offset
  bounds-checked; nothing traps; cancellation asked at least every 1 MiB of output. Every refusal is a sentence ("The stored model is
  damaged." for any malformed frame, "The stored model is larger than <limit>." over a limit, "The stored model uses a zstd dictionary, which
  isn't supported." for a dictionary id).
- KiCad's own checksum (MurmurHash3 or SHA-256) is not checked (spec). The zstd frame's content checksum (XXH64, low 32 bits) IS checked when
  present: a mismatch is "The stored model is damaged.".
- Swift Testing; `swiftlint lint --strict`; format 13, 14 test targets, 89 nodes. Commit trailer: `Co-Authored-By: Claude Opus 5.5
  <noreply@anthropic.com>` and `Claude-Session: https://claude.ai/code/session_0195iKYokoi2BJLpboZBys76`.

## Rulings

- R1. Only `(type model)` entries are kept; their base64 text is kept undecoded (a `String` from the `|…|` block) until a footprint names it,
  so a board with stored datasheets costs nothing. The reader stops skipping `embedded_files` (KI-1 skipped it).
- R2. Lookup: the footprint's own `embedded_files` first, then the board's (facts §2); names compared exactly.
- R3. A stored model is cached in `ComponentModelCache` keyed by the SHA-256 of its base64 text (`CreatorGraph`'s `SHA256` is not reachable
  from `CreatorPCB`; the node computes it) plus the format; it needs no dependency (the board's own stamp covers it).
- R4. An empty `(data)` (KiCad 9.0.0's writer bug) is "couldn't be read … (it is empty)". A name that isn't in either table is "wasn't
  found: kicad-embed://<name>".

## Review Focus

1. A zstd frame using every block and table kind (raw, RLE, compressed; raw, RLE, Huffman 1 and 4 streams and treeless literals;
   predefined, RLE, FSE and repeat sequence tables; repeat offsets) decodes byte-exact. Task 2's fixtures come from `zstd -19`, `--ultra -22`,
   `--long`, small and large inputs, and a crafted RLE frame.
2. A damaged or hostile frame (truncated at every byte of a small frame, a flipped bit at every byte, a content size of 2^60, a window of
   2^40, an offset past the output, a Huffman table with weights that don't sum, an FSE table with too many states): a sentence, never a trap
   or hang. Task 2's exhaustive truncation and bit-flip loops.
3. A board with 40 stored models of 2 MB each reads in one pass and keeps only base64 text until used. Task 3.
4. A footprint that names a stored model and the same name on disk: the stored one wins (the name says `kicad-embed://`). Task 4.

---

### Task 1: `Base64` and `XXH64`

**Files:** Create `Sources/CreatorPCB/Embedded/Base64.swift`, `XXH64.swift`; `Tests/CreatorPCBTests/Base64Tests.swift`, `XXH64Tests.swift`.

```swift
public enum Base64 { /// Standard alphabet, `=` padding, whitespace ignored; any other byte, misplaced padding or a bad length → nil.
    public static func decode(_ text: Substring.UTF8View, limit: Int) -> Data? }   // nil also when the result would exceed `limit`
public enum XXH64 { public static func hash(_ bytes: UnsafeRawBufferPointer, seed: UInt64 = 0) -> UInt64 }
```
- [ ] Tests: RFC 4648 vectors ("", "f" … "foobar"); 76-column lines with CRLF; bad character; bad padding; over limit. XXH64 against vectors
  computed with `zstd`'s or the reference values ("" seed 0 = 0xEF46DB3751D8E999; "a" = 0xD24EC4F1A98C6E5B; 100 bytes 0…99 — compute with
  a tool and pin). Commit "KiCad import: base64 and XXH64".

### Task 2: `ZstdDecoder`

**Files:** Create `Sources/CreatorPCB/Embedded/Zstd/` (frame and block reading, `ZstdBitReader` (backward), `ZstdFSE`, `ZstdHuffman`,
`ZstdLiterals`, `ZstdSequences`, `ZstdDecoder`); `Tests/CreatorPCBTests/ZstdDecoderTests.swift`, `ZstdFixtures.swift` (base64 strings of
frames and the SHA-256 or the bytes of their plain text; generate with `zstd` and a small script whose command lines are in a comment).

```swift
public struct ZstdProblem: Error, Equatable, Sendable { public let message: String }
public enum ZstdDecoder {
    /// One frame (skippable frames before it are skipped; data after the frame is refused).
    public static func decode(_ frame: Data, limit: Int, isCancelled: () -> Bool) throws -> Data   // ZstdProblem or CancellationError
}
```
- [ ] Tests: each fixture byte-exact; an empty input frame; `--no-check` frame; checksum mismatch; dictionary id refused; content size over
  limit refused before decoding (no allocation: test with limit 1 KB and a frame that states 1 GB); unknown size over limit stops; every
  truncation of a 2 KB frame and every single-bit flip of it: either the right bytes or a `ZstdProblem`, never a trap (time-boxed: the loop
  over ~16k mutations must finish in under 10 s in debug); a 2,000-case seeded fuzz. Commit "KiCad import: a zstd decoder".

### Task 3: The board keeps its stored models

**Files:** Modify `Sources/CreatorPCB/Board/KiCadBoardReader*.swift` (stop skipping `embedded_files`; read board-level and footprint-level
tables), `KiCadBoard.swift` (`public struct EmbeddedFile { name: String; base64: String }`, `KiCadBoard.embeddedModels: [EmbeddedFile]`,
`Footprint.embeddedModels: [EmbeddedFile]`); the S-expression limits for a `|…|` block (the board's 256 MB bound stays; check the existing
cap); `Tests/CreatorPCBTests/EmbeddedFilesTests.swift`.
- [ ] Tests: a board with two model files and a datasheet keeps the two (R1); a footprint table; an empty `(data)`; a version before 20240706
  ignores bars as KiCad does (the existing reader rule); memory: 40 × 2 MB of base64 reads with one copy (assert the strings' total equals the
  input's base64 size, no decoded `Data` kept). Commit "KiCad import: the board keeps its stored models".

### Task 4: The node reads stored models

**Files:** Modify `Sources/CreatorNodes/Import/BoardComponents*.swift`, `ComponentModelCache.swift`; tests in
`Tests/CreatorNodesTests/ImportKiCadStoredModelsTests.swift` (fixtures: compress a test STEP with `zstd` at test time? No: the test cannot
assume the tool. Build the frame in the test with a minimal zstd ENCODER of raw blocks (a frame header with the content size, raw blocks of
≤128 KB, an XXH64 checksum) in a test helper, plus one checked-in compressed fixture from Task 2 for a VRML model.)
- [ ] Behaviour: `.embedded(name:)` → R2 lookup → base64 decode (limit: the format's limit × 4/3 + slack) → `ZstdDecoder.decode` (limit by
  the name's `ModelFormat`) → the format pipeline (STEP, compressed STEP, IGES, VRML, X3D, IDF). R3 cache key. R4 sentences. KI-2's "models
  stored in the board aren't read yet" reason removed.
- [ ] Tests: a stored STEP placed like the same STEP on disk (bounds equal); a stored VRML; a footprint-level table wins over the board's;
  missing name; empty data; damaged frame → "couldn't be read: <name> (it is damaged)"; two nodes read it once; `components` off decodes
  nothing. Commit "KiCad import: models stored in the board".

### Task 5: Docs and the suite

CLAUDE.md (KI-4 done; `Base64`, `XXH64`, `ZstdDecoder` in `CreatorPCB/Embedded`), human checks (a KiCad 9 board with embedded models reads
complete with the project folder renamed away), the spec's status, full suite macOS (14 lines) and Linux, lint. Commit "Docs: KI-4".
