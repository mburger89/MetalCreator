# Packaging MetalCreator

How to build, check and (by hand) notarize the macOS app (`MetalCreator.app`, below), and how the Linux tarball, the Linux AppImage and
the Windows zip are built (further down, from "Linux: a tarball"). The macOS design and its reasons:
`docs/superpowers/specs/2026-10-09-packaging-design.md`; Linux and Windows are sub-project xp-2 of
`docs/superpowers/specs/2026-10-13-cross-platform-design.md` (section 3), plan `docs/superpowers/plans/2026-10-21-xp-2-occt-linux-windows.md`.

## Build

```sh
scripts/package-app.sh
```

writes `dist/MetalCreator.app` (about 50 MB), signed ad hoc, and ends by running `scripts/verify-app.sh` on it. It
needs the Xcode command-line tools and Homebrew's `opencascade` (the build links it; the app then carries its own
copy). `METALCREATOR_DIST_DIR=/some/folder` writes the app there instead. A run that passes replaces the app; one
that fails (for example an unknown signing identity) prints why and leaves the previous app alone.

An ad-hoc signature is enough to run the app on this Mac. A copy downloaded or AirDropped to another Mac is
quarantined, and Gatekeeper refuses an ad-hoc app: open it with Control-click ▸ Open, or allow it in System
Settings ▸ Privacy & Security.

## Check

```sh
scripts/verify-app.sh [path/to/MetalCreator.app]
```

re-checks a bundle, for example after moving it: the plist, the signature (`codesign --verify --deep --strict`), that
no binary in it links or searches `/opt/homebrew` or `/usr/local`, that `LSMinimumSystemVersion` covers every bundled
binary, and that `MetalCreator --self-test` passes with an empty environment and Homebrew's folders unreadable
(`sandbox-exec`). The bundled libraries come from Homebrew bottles built for macOS 27, so the app needs macOS 27 even
though `Package.swift` says 26; the script prints a note saying so.

The binary's headless flags also work on their own:

```sh
dist/MetalCreator.app/Contents/MacOS/MetalCreator --version     # MetalCreator 0.1.0 (2)
dist/MetalCreator.app/Contents/MacOS/MetalCreator --self-test   # OCCT, STEP/STL export, MetalUI's shaders
swift run MetalCreatorApp --self-test                           # the same checks, unpackaged
```

## The version

`AppBundleInfo` (`Sources/CreatorApp/AppBundleInfo.swift`) is the one source: `version` is the marketing version,
`build` the build number. Raise `build` for every build handed to someone. The bundle's `Info.plist` is generated from
it; never edit a packaged plist by hand (it would also break the signature).

## Signing with a Developer ID

```sh
security find-identity -v -p codesigning       # the identities in your keychain
METALCREATOR_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/package-app.sh
```

signs every library and the app with that identity, the hardened runtime and a secure timestamp (needs the network).
Under the hardened runtime dyld ignores `DYLD_PRINT_LIBRARIES`, so `verify-app.sh` says it has no load list and relies
on its link check. **Unverified**: no Developer ID build was made while writing this.

## Notarizing (manual, unverified)

Notarization needs your Apple ID, so it isn't scripted. Once, store an app-specific password in the keychain:

```sh
xcrun notarytool store-credentials metalcreator --apple-id you@example.com --team-id TEAMID
```

Then, after a Developer ID build:

```sh
ditto -c -k --keepParent dist/MetalCreator.app dist/MetalCreator.zip
xcrun notarytool submit dist/MetalCreator.zip --keychain-profile metalcreator --wait
xcrun stapler staple dist/MetalCreator.app
spctl --assess --type execute --verbose dist/MetalCreator.app    # "accepted, source=Notarized Developer ID"
```

If the submission is rejected, `xcrun notarytool log <submission id> --keychain-profile metalcreator` says why.

## Not yet

No app icon on macOS (Finder shows the generic one; the Linux files carry a placeholder), no disk image and arm64 only.

## Documents

The `.mcgraph` document type in `Info.plist` comes from `AppBundleInfo` (never edited by hand). A Finder double-click,
a drop on the Dock icon and `open -a MetalCreator.app file.mcgraph` reach the app as MetalUI open-URL events
(`App.onOpenURL`, set before `app.run()` in `Sources/MetalCreatorApp/main.swift`) and open the file through
`AppModel.openRequested(_:)`: with unsaved changes the app asks first, and several dropped files leave the last one
open. No `NSDocumentClass` is declared; MetalUI's probe (`docs/probes/appkit-open-without-document-class.swift`) found
AppKit's "cannot open files in this format" alert only for an application delegate without `application(_:open:)`,
which MetalUI's has. A Finder double-click and a Dock drop themselves are human checks AS-6 and AS-7 (MetalUI has not
measured them either, its AS9).

## Linux: a tarball

```sh
scripts/linux-test.sh package      # on this Mac, in Docker (OrbStack); CI runs the same on x86_64 and aarch64
scripts/package-linux.sh           # on a Linux machine with Swift 6.4, SDL 3.4, AccessKit, OpenCascade 7.9 and patchelf
```

write `dist/MetalCreator-<version>-linux-<arch>.tar.gz`. Unpacked, the folder holds `MetalCreator` (a release build), `lib/` (the Swift
runtime's libraries, OpenCascade's `libTK*.so.7.9`, `libSDL3.so.0` and whatever else `ldd` names that is not glibc or
the C++ runtime; linking the Swift runtime statically does not work with Foundation here), `MetalUISDLShaders/` (MetalUI's compiled SDL shaders, which the backend looks for beside the executable first,
ruling `PX-P`), `share/applications/com.metalcreator.MetalCreator.desktop`, `share/mime/packages/com.metalcreator.MetalCreator.xml`,
`share/icons/hicolor/256x256/apps/com.metalcreator.MetalCreator.png` (a placeholder icon), `install.sh` and `share/doc/metalcreator/` (the licences: OpenCascade's LGPL 2.1 and its exception, MetalUI's third-party notices and the
licence files they name). The executable's RUNPATH is set to `$ORIGIN/lib` and each bundled library's to `$ORIGIN` (`patchelf`; the
build's `/opt/occt/lib` and the toolchain's `/usr/lib/swift/linux` are left out), so the folder runs from anywhere and finds
only its own libraries. It still needs the machine's glibc (the build image is Ubuntu 24.04, glibc 2.39), libstdc++ and, to draw, a
Vulkan driver.

`scripts/linux-test.sh package` then unpacks the tarball in a clean `ubuntu:24.04` (no Swift, no `/opt/occt`, no MetalUI checkout) and
runs `--version` and `--self-test` there: OpenCascade builds, measures, meshes and exports a cube, and the SDL shaders are found beside
the executable. It also runs `desktop-file-validate` on the entry. The AppImage (next section) is packed from this same tree; both are shipped (user decision 2 of the xp-2 plan).

OpenCascade itself is built from source (commit `a016080b…`, tag `V7_9_3`) in the `occt` stage of `scripts/linux/Dockerfile`; the
toolkits are listed there. Raising the version means changing `OCCT_COMMIT` and rebuilding the stage (about 13 minutes with 6 jobs on
this Mac). Locally Docker's layer cache keeps it; in CI buildx's cache in the GitHub Actions cache does (scope `xp-occt-<arch>`;
GitHub evicts an entry unused for seven days, and the least recently used ones when the repository passes 10 GB, and the next run then
builds it again; a branch's caches are visible to that branch and the default branch only).

## Linux: an AppImage

```sh
scripts/linux-test.sh package      # the tarball, then the AppImage from it, each run in a clean ubuntu:24.04
scripts/package-appimage.sh        # on a Linux machine, after scripts/package-linux.sh
```

write `dist/MetalCreator-<version>-linux-<arch>.AppImage`. It holds the tarball's tree (so the same libraries, the same `RUNPATH
$ORIGIN/lib` and `MetalUISDLShaders`) as `usr/metalcreator` in an AppDir whose root has `AppRun`, the same desktop entry and icon the
tarball installs, and a `.DirIcon` link; appimagetool packs it. The tool is appimagetool 1.9.1 and the runtime the type2 runtime
20251108, both third-party and both fetched by the script while packaging, pinned by version and sha256 and checked before they run.
They are no dependency of MetalCreator (nothing links them; a version bump changes the hashes in `scripts/package-appimage.sh`, whose
presence `AppImageRecipeTests` checks). No FUSE is needed to build or check the file: appimagetool runs with
`--appimage-extract-and-run`, and so does the clean-Ubuntu run (`./MetalCreator-….AppImage --appimage-extract-and-run --self-test`).
Running an AppImage normally needs FUSE on the user's machine, as every AppImage does; without it the same flag runs it. The packer
adds a download of about 16 MB (kept in `dist/tools`) and one squashfs compression of the tarball's tree to `package`; with a stub
tree the script took 1.3 s, and the time on the real tree is recorded in the plan's measured results once it has been run.

The AppImage does not register the `.mcgraph` type itself (plan decision 2: `install.sh` registers the folder it sits in, and an
AppImage has no stable folder). An AppImage integration tool such as AppImageLauncher or appimaged installs the image's desktop entry;
the MIME type can be registered by hand:

```sh
./MetalCreator-<version>-linux-<arch>.AppImage --appimage-extract 'usr/metalcreator/share/mime/packages/*.xml'
install -D -m 644 squashfs-root/usr/metalcreator/share/mime/packages/com.metalcreator.MetalCreator.xml \
    ~/.local/share/mime/packages/com.metalcreator.MetalCreator.xml
update-mime-database ~/.local/share/mime
```

Human check XP-19 runs it on a desktop.

## Windows: a zip

CI's Windows job runs `scripts\package-windows.ps1` (nothing here runs on Windows; the job is the only check):

```powershell
scripts\package-windows.ps1 -BuildFlags @("-Xcc", "-I$env:SDL3_INCLUDE", "-Xswiftc", "-L$env:SDL3_LIB", …) -SdlRoot $env:SDL3_ROOT
```

It writes `dist\MetalCreator-<version>-windows-x64.zip` with `MetalCreator.exe`, every DLL the executable needs beside it (OpenCascade's
from `OCCT_PREFIX\bin`, `SDL3.dll`, the Swift runtime's and the Visual C++ runtime's, found by following the `DLL Name:` lines of
`llvm-objdump -p` (or `dumpbin /dependents` when the toolchain has no objdump); Windows' own DLLs are left out), `MetalUISDLShaders\`,
`register-mcgraph.ps1` and `licenses\`. The Swift runtime's folder is looked up (by `swiftCore.dll`, under the `Swift` folder that
`swift.exe` and `SDKROOT` sit in), not written down. The script then unpacks the zip and runs `--self-test` with only Windows'
folders on `PATH` and MetalUI's checkout moved aside (the SDL backend falls back to the shaders in its source tree), so a missing DLL
or shader directory fails the job. It packages a release build: CI makes it in its own step (`swift build -c release --product
MetalCreatorApp`, then `-NoBuild`), because the suite is a debug build.

OpenCascade on Windows is vcpkg's `opencascade` port at 7.9.3, release and debug libraries (triplet `x64-windows`), pinned by the
vcpkg commit in `.github/workflows/xp.yml` (`VCPKG_COMMIT`), which `packaging/windows/vcpkg.json` repeats as its `builtin-baseline`
(`CIPinTests` checks they agree). Both sets are installed because the suite is a debug build: `Package.swift` links `debug/lib` for a
debug build and `lib` for a release one, so Swift's and the shim's C runtime is the same as OpenCascade's on each side. To build on your
own Windows machine: install vcpkg at that commit, run
`vcpkg install --triplet x64-windows --x-manifest-root=packaging\windows --x-install-root=C:\occt-install`, and set
`OCCT_PREFIX=C:/occt-install/x64-windows` and `PATH` to its `debug\bin` (for `swift test`) or `bin` (for a release build) before
`swift build`. CI saves vcpkg's binary cache right after the install, so a later red step does not lose the build.

`Package.swift` reads `OCCT_PREFIX` on every platform; its defaults are Homebrew's prefix on macOS, `/opt/occt` on Linux (the test
image's) and `C:/occt` on Windows.

## Documents on Linux and Windows

A file manager runs `MetalCreator %F` (the desktop entry's `Exec=`) or `MetalCreator.exe "%1"` (the file type
`register-mcgraph.ps1` registers). `LaunchCommand` takes every leading non-flag argument as a document; `main.swift` hands them to
MetalUI as `app.open(…)` after the first window, and MetalUI's single-instance forwarding (S7) sends the paths of a second launch to
the running instance, which opens them through `App.onOpenURL` and `AppModel.openRequested(_:)`. A file dropped on the application
itself (SDL's drop with no window) reaches the same handler as `Platform.onOpenURLs` (gap XP-G5). Several files leave the last one open,
as on macOS.

On Linux, `install.sh` (run from the unpacked folder) copies the desktop entry to `~/.local/share/applications` with `Exec=` pointing
at the folder's `MetalCreator`, the MIME type `application/x-metalcreator-graph` (glob `*.mcgraph`, a kind of `application/json`)
to `~/.local/share/mime/packages` and the placeholder icon to `~/.local/share/icons/hicolor/256x256/apps`, then runs
`update-mime-database` and `update-desktop-database` where they exist. `install.sh --remove` undoes it. The entry says
`Icon=com.metalcreator.MetalCreator` and `StartupWMClass=com.metalcreator.MetalCreator`. A desktop shell matches the running window to
the entry by the window's application id, which is that name: MetalUI sets SDL's `SDL_APP_ID` hint from the id
`SDLPlatform.launchingSingleInstance(id: AppBundleInfo.identifier, …)` is given (MetalUI `docs/packaging.md`, section 3; gap XP-G13,
fixed), so MetalCreator sets nothing itself. The icon is a placeholder (`packaging/linux/com.metalcreator.MetalCreator.png`).
The AppImage carries the same entry and icon and leaves the file type to a manual step (see its section).

On Windows, `register-mcgraph.ps1` (run from the unpacked folder, no administrator rights) writes the `.mcgraph` association under
`HKEY_CURRENT_USER\Software\Classes`; `-Remove` deletes it. The Linux files and the Windows script are not verified on a desktop: human checks XP-16, XP-17 and XP-19.

## Signing

None of the tarball, the AppImage and the zip is signed (user decision 3; spec section 6: Windows signing is out of scope). Windows SmartScreen warns about an
unsigned download.
