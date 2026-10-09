# Packaging MetalCreator.app

How to build, check and (by hand) notarize the app. The design and its reasons:
`docs/superpowers/specs/2026-10-09-packaging-design.md`.

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
dist/MetalCreator.app/Contents/MacOS/MetalCreator --version     # MetalCreator 0.1.0 (1)
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

No app icon (Finder shows the generic one), no disk image, arm64 only, and a double-clicked `.mcgraph` opens the app
without opening the file until MetalUI delivers open-document events (`docs/metalui-gaps.md` M6-d).
