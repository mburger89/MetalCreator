# MetalCreator — Packaging Design (Track D)

**Date:** 2026-10-09. **Status:** approved for planning. **Binding spec:** `2026-10-07-metalcreator-vertical-slice-design.md`
(§5.2 and §11 deferred "Bundling OCCT into a signed, distributable `.app`"; this document takes that item on).
**Plan:** `docs/superpowers/plans/2026-10-09-packaging.md`.

## Goal

One command builds `dist/MetalCreator.app`: a release build of the app that runs on this Mac with Homebrew off the
dynamic loader's path, signed, with `.mcgraph` registered as its document type, and checked by a script before
anyone opens it. The app's code doesn't change, apart from three headless flags the script needs.

## Approach

`scripts/package-app.sh` (bash 3.2, Xcode command-line tools only):

1. `swift build -c release --product MetalCreatorApp`, then `--show-bin-path` for the products directory (Swift 6.4's
   default build system writes `.build/out/Products/Release`; the script never hard-codes it).
2. Lay out `MetalCreator.app/Contents/{MacOS,Frameworks,Resources}`. The binary is copied as `MacOS/MetalCreator`;
   every SwiftPM resource bundle in the products directory (today only MetalUI's `MetalUI_MetalUIRender.bundle`, the
   shader sources) goes into `Resources`, where MetalUI's `ShaderLibrary.candidateDirectories` looks first in an app.
3. Walk `otool -L` from the binary. Every library outside `/usr/lib` and `/System` is copied (the real file, not
   Homebrew's symlink) into `Frameworks` under its install name's file name, and walked in turn; `@rpath`,
   `@loader_path` and `@executable_path` names are resolved against the original file's location. On this Mac that is
   31 libraries: OCCT's 19 linked toolkits plus the 8 that its STEP toolkit pulls in (`TKXCAF`, `TKVCAF`, `TKCAF`,
   `TKLCAF`, `TKCDF`, `TKV3d`, `TKService`, `TKHLR` — the visualisation and document frameworks), TBB (`libtbb`,
   `libtbbmalloc`), FreeType and libpng.
4. `install_name_tool`: every bundled library's id becomes `@rpath/<name>`, every reference to a bundled library
   becomes `@rpath/<name>`, every `LC_RPATH` is deleted, and the executable gains the one rpath
   `@executable_path/../Frameworks`. `Package.swift` is unchanged; the `/opt/homebrew` rpath its linker flags embed is
   one of the rpaths deleted.
5. Copy each Homebrew keg's licence files into `Resources/Licenses/<formula>/`; a keg without one stops the script.
   MetalUI's `THIRD-PARTY-NOTICES.md` and stb_image's licence go into `Resources/Licenses/MetalUI/`.
6. Write `Info.plist` by running the built binary: `MetalCreatorApp --info-plist <minimum macOS>`.
7. Sign inside-out: each library in `Frameworks`, then the app.
8. Run `scripts/verify-app.sh` on it, and only then move it to `dist/MetalCreator.app`. The app is assembled in a
   temporary folder, so a failed run (a missing licence, an unknown signing identity, a failed check) leaves the
   previous app in `dist/` untouched.

`scripts/verify-app.sh [app]` checks a finished bundle, so it can be run again on a moved copy: the plist lints and
names an executable that exists; `codesign --verify --deep --strict` passes; no Mach-O file in the bundle links or
searches `/opt/homebrew` or `/usr/local`, and every `@rpath` library it links is in `Frameworks`;
`LSMinimumSystemVersion` is no older than any bundled binary's `minos`; and `MetalCreator --self-test` passes with
an empty environment (`env -i`, so no `DYLD_*` variable) under `sandbox-exec` with a profile that denies every read of
`/opt/homebrew` and `/usr/local` — the script first proves the profile bites (`ls /opt/homebrew` must fail) — while
`DYLD_PRINT_LIBRARIES` shows that every image dyld loaded came from the bundle or the system.

## Decisions

1. **A script, not an Xcode project or a SwiftPM plugin.** The package stays the single build description; packaging
   is a post-build step. No tool beyond the Xcode command-line tools (`otool`, `install_name_tool`, `codesign`,
   `plutil`) and macOS's own `sandbox-exec`, `find`, `awk` (user decision: no third-party tools).
2. **The version has one source: `AppBundleInfo` in `CreatorApp`** (name, bundle identifier
   `com.metalcreator.MetalCreator`, version `0.1.0`, build `1`, the document type's name). The bundle's `Info.plist`
   is generated from it by the binary (`--info-plist`), never written by hand, so `swift test` pins its content.
3. **Three headless flags, parsed by `LaunchCommand` (tested):** `--version`, `--self-test` (exit 0 or 1) and
   `--info-plist <version>`; an unknown `--flag` prints the usage and exits 64. Anything else starting with `-` is the
   system's (`-psn_…`, `-NSSomeDefault value`) and opens an empty window, as before; any other first argument is still
   the file to open, handed to the app as a Finder open is (MetalUI C8).
4. **`--self-test` runs the code paths a missing library would break**, without a window: a 10 mm cube on OCCT
   (volume and mesh), STEP and STL export into a temporary folder (OCCT's data-exchange toolkits; they need none of
   OCCT's resource files — measured with Homebrew unreadable), and MetalUI's shader bundle found and compiled on the
   Metal device (`ShaderLibrary.make`, what `App()` does). It runs from synchronous top-level code in a main-actor task
   drained by `RunLoop.main`, so `main.swift` keeps MetalUI's rule that `app.run()` is called from synchronous code.
5. **`LSMinimumSystemVersion` is the newest `minos` among the bundled binaries.** `Package.swift` says macOS 26, but
   Homebrew's bottles on this Mac are built for macOS 27, so the plist says 27.0 and the script prints a note. A
   plist claiming 26 would let macOS 26 launch the app into a dyld failure. Shipping to macOS 26 needs OCCT and its
   dependencies built with a macOS 26 deployment target, which is out of scope.
6. **Ad-hoc signing by default; a real identity through `METALCREATOR_SIGN_IDENTITY`** (user decision). With an
   identity, every library and the app are signed with the hardened runtime and a secure timestamp, as notarization
   requires. Ad hoc never turns the hardened runtime on: its library validation refuses ad-hoc libraries (measured:
   "mapping process and mapped file (non-platform) have different Team IDs"). No entitlements are needed: Metal
   compiles shaders from source without JIT, and OCCT needs none.
7. **No notarization** (user decision: it needs the user's Apple credentials). `docs/packaging.md` documents the
   manual `notarytool` and `stapler` steps; they are unverified here.
8. **`.mcgraph` is declared now**: a `CFBundleDocumentTypes` entry (role Editor, rank Owner) and an exported type
   declaration (`com.metalcreator.mcgraph`, conforming to `public.json`, extension `mcgraph`) — the identifier
   `ContentType.mcgraph` already uses. Finder names the kind and a double-click or Dock drop opens the file in the
   app through MetalUI's `App.onOpenURL` (gap M6-d, MetalUI C8; no `NSDocumentClass` is needed, MetalUI's probe).
9. **No app icon yet.** `CFBundleIconFile` is omitted and Finder shows the generic app icon. An icon is a design task
   of its own; MetalUI's `docs/packaging.md` has the `.icns` recipe for when one exists.
10. **The artefacts go to `dist/`** (`METALCREATOR_DIST_DIR` overrides it), which is git-ignored. Each run that
    passes replaces the app; one that fails leaves it alone.
11. **Licences travel with the libraries** (OCCT's LGPL 2.1 and its exception, TBB's Apache 2.0, FreeType's FTL,
    libpng's licence). The stb_image notice for code MetalUI compiles into the binary comes from MetalUI's
    `THIRD-PARTY-NOTICES.md` (gap P-a, fixed in MetalUI 67a579e).

## Out of scope

Notarization and stapling (manual, documented); a disk image or installer; an app icon; universal (x86_64) builds —
Homebrew's arm64 bottles are arm64 only; shipping to macOS 26 (decision 5); building OCCT from source; open-document
events (MetalUI C8).

## Testing

`swift test`: `AppBundleInfoTests` (the plist's keys, the version line, the `.mcgraph` type against
`ContentType.mcgraph`), `LaunchCommandTests` (every flag, usage errors, the system's own arguments), `SelfTestTests`
(all checks pass on OCCT and the scratch folder is removed; failures are worded and fail the run) and
`PackagingScriptTests` (both scripts are executable and parse with `bash -n`). The packaged bundle is checked by
`scripts/verify-app.sh`, and a person runs human-check group P (Finder launch, a moved copy, the document type,
optionally a Developer ID build).
