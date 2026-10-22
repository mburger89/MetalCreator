#!/bin/bash
# Builds dist/MetalCreator-<version>-linux-<arch>.tar.gz: a release build of MetalCreatorApp, the Swift runtime, OpenCascade, SDL3
# and the other non-system shared libraries it needs in lib/, MetalUI's compiled SDL shaders in
# MetalUISDLShaders beside the executable, the desktop entry, MIME type and icon for .mcgraph files, install.sh, and the licences.
# Unpacked, the folder runs from anywhere: the executable's rpath is $ORIGIN/lib (Package.swift).
#
# usage: scripts/package-linux.sh        (on Linux; scripts/linux-test.sh package runs it in the test image)
#   METALCREATOR_DIST_DIR   where the tarball is written (default: <repo>/dist).
#   METALCREATOR_SCRATCH    SwiftPM's build folder (default: <repo>/.build).
#   OCCT_PREFIX             OpenCascade's install prefix (default /opt/occt), for its licence files.
# Needs MetalUI beside this repository (../MetalUI), patchelf, and the libraries `ldd` names for the built executable.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${METALCREATOR_DIST_DIR:-$ROOT/dist}"
SCRATCH="${METALCREATOR_SCRATCH:-$ROOT/.build}"
OCCT="${OCCT_PREFIX:-/opt/occt}"
METALUI="$(cd "$ROOT/../MetalUI" && pwd -P)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

step() { printf '==> %s\n' "$*"; }
fail() { printf 'package-linux: %s\n' "$*" >&2; exit 1; }

# Libraries the system provides on every Linux the app runs on (glibc, the C++ runtime): they are never bundled, because a
# bundled glibc breaks against the host's loader. The Swift runtime is bundled: `--static-swift-stdlib` does not link here
# (Foundation's ICU symbols are undefined, measured with Swift 6.4 on Ubuntu 24.04).
is_system() {
    case "$1" in
        linux-vdso.so.*|ld-linux-*|libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|libutil.so.*|libresolv.so.*) return 0 ;;
        libgcc_s.so.*|libstdc++.so.*) return 0 ;;
        *) return 1 ;;
    esac
}

step "Building MetalCreatorApp (release)"
swift build --package-path "$ROOT" -c release --product MetalCreatorApp --scratch-path "$SCRATCH"
BIN_DIR="$(swift build --package-path "$ROOT" -c release --product MetalCreatorApp --scratch-path "$SCRATCH" --show-bin-path)"
BINARY="$BIN_DIR/MetalCreatorApp"
VERSION="$("$BINARY" --version | sed -nE 's/^MetalCreator ([0-9][^ ]*) .*/\1/p' | head -n 1)"
[ -n "$VERSION" ] || fail "couldn't read the version from --version"
NAME="MetalCreator-$VERSION-linux-$(uname -m)"
FOLDER="$WORK/MetalCreator"

step "Assembling $NAME"
mkdir -p "$FOLDER/lib" "$FOLDER/share/applications" "$FOLDER/share/mime/packages" "$FOLDER/share/icons/hicolor/256x256/apps" "$FOLDER/share/doc/metalcreator"
cp "$BINARY" "$FOLDER/MetalCreator"
# The build's search path (/opt/occt/lib, the image's OpenCascade) stays out of the shipped binary: it looks in its own lib/ only,
# so an unrelated OpenCascade on a user's machine can never be found instead (or after) the bundled one.
chmod u+w "$FOLDER/MetalCreator"
patchelf --set-rpath '$ORIGIN/lib' "$FOLDER/MetalCreator"
[ "$(patchelf --print-rpath "$FOLDER/MetalCreator")" = '$ORIGIN/lib' ] || fail "the executable's RUNPATH isn't \$ORIGIN/lib"
cp "$ROOT/packaging/linux/install.sh" "$FOLDER/install.sh"
cp "$ROOT/packaging/linux/com.metalcreator.MetalCreator.desktop" "$FOLDER/share/applications/"
cp "$ROOT/packaging/linux/com.metalcreator.MetalCreator.xml" "$FOLDER/share/mime/packages/"
cp "$ROOT/packaging/linux/com.metalcreator.MetalCreator.png" "$FOLDER/share/icons/hicolor/256x256/apps/"
# MetalUI's SDL backend looks for its compiled shaders in MetalUISDLShaders beside the executable first (ruling PX-P).
SHADERS="$METALUI/Backends/SDL/Shaders/compiled"
[ -f "$SHADERS/SOURCE.sha256" ] || fail "MetalUI's compiled shaders are missing: $SHADERS/SOURCE.sha256"
cp -R "$SHADERS" "$FOLDER/MetalUISDLShaders"

step "Copying the non-system libraries it links, transitively"
ldd "$BINARY" > "$WORK/ldd.txt"
grep -q "not found" "$WORK/ldd.txt" && fail "ldd can't find a library: $(grep 'not found' "$WORK/ldd.txt" | head -n 1)"
count=0
while read -r name arrow path _; do
    [ "$arrow" = "=>" ] || continue
    is_system "$name" && continue
    cp -L "$path" "$FOLDER/lib/$name"
    chmod u+w "$FOLDER/lib/$name"
    # RUNPATH is not inherited, so each bundled library names its own folder for the ones it loads in turn.
    patchelf --set-rpath '$ORIGIN' "$FOLDER/lib/$name"
    count=$((count + 1))
done < "$WORK/ldd.txt"
printf '    %s libraries\n' "$count"
[ -f "$FOLDER/lib/libTKernel.so.7.9" ] || fail "OpenCascade's libTKernel.so.7.9 isn't among the linked libraries"

step "Copying the licences"
DOC="$FOLDER/share/doc/metalcreator"
for f in LICENSE_LGPL_21.txt OCCT_LGPL_EXCEPTION.txt; do
    [ -s "$OCCT/share/licenses/$f" ] || fail "OpenCascade's $f is missing from $OCCT/share/licenses"
    cp "$OCCT/share/licenses/$f" "$DOC/"
done
# SDL3 (zlib) and the Swift runtime (Apache-2.0 with the Runtime Library Exception) are bundled in lib/: their licences ship too.
SDL_LICENSE="${SDL_LICENSE_FILE:-/usr/share/licenses/SDL3/LICENSE.txt}"
[ -s "$SDL_LICENSE" ] || fail "SDL3's licence is missing: $SDL_LICENSE"
cp "$SDL_LICENSE" "$DOC/SDL3-LICENSE.txt"
[ -s "$ROOT/packaging/licenses/Swift-LICENSE.txt" ] || fail "packaging/licenses/Swift-LICENSE.txt is missing"
cp "$ROOT/packaging/licenses/Swift-LICENSE.txt" "$DOC/Swift-LICENSE.txt"
cp "$METALUI/THIRD-PARTY-NOTICES.md" "$DOC/MetalUI-THIRD-PARTY-NOTICES.md"
for f in CStbImage/LICENSE CFreeType/FTL.TXT CFreeType/LICENSE.TXT CHarfBuzz/COPYING CUnibreak/LICENCE CSheenBidi/LICENSE; do
    cp "$METALUI/Sources/$f" "$DOC/$(dirname "$f")-$(basename "$f")"
done

# NOTICE.txt: where OpenCascade's source is and that its shared libraries may be replaced (LGPL-2.1 section 6). The commit is the
# one the image was built from (the Dockerfile's OCCT_COMMIT), so the notice cannot name a different one.
OCCT_COMMIT="$(sed -nE 's/^ARG OCCT_COMMIT=([0-9a-f]{40})$/\1/p' "$ROOT/scripts/linux/Dockerfile")"
[ -n "$OCCT_COMMIT" ] || fail "couldn't read OCCT_COMMIT from scripts/linux/Dockerfile"
OCCT_LIBS="$(cd "$FOLDER/lib" && ls libTK*.so.7.9 | sed 's/^/                lib\//')"
[ -n "$OCCT_LIBS" ] || fail "no libTK*.so.7.9 in lib/"
cat > "$DOC/NOTICE.txt" <<NOTICE
MetalCreator $VERSION: third-party software shipped in this package

OpenCascade Technology (OCCT) 7.9
  Licence:   GNU LGPL version 2.1 with the OCCT exception (LICENSE_LGPL_21.txt and OCCT_LGPL_EXCEPTION.txt, in this folder).
  Source:    https://github.com/Open-Cascade-SAS/OCCT, tag V7_9_3, commit $OCCT_COMMIT (built unmodified).
  Libraries: the shared libraries
$OCCT_LIBS
  Relinking: OCCT is linked dynamically. You may replace those libraries with your own build of OCCT 7.9, modified or not, and
             MetalCreator will use them: the executable looks in its own lib/ folder only (RUNPATH \$ORIGIN/lib).

SDL3 (lib/libSDL3.so*): zlib licence, SDL3-LICENSE.txt. Source: https://github.com/libsdl-org/SDL, tag release-3.4.16.

Swift runtime (lib/libswift*.so and the libraries Foundation needs): Apache License 2.0 with the Runtime Library Exception,
Swift-LICENSE.txt. Source: https://github.com/swiftlang/swift, release 6.4.

MetalUI and the libraries it vendors (stb_image, FreeType, HarfBuzz, libunibreak, SheenBidi): MetalUI-THIRD-PARTY-NOTICES.md and the
licence files named after each library, in this folder. AccessKit is linked statically into the executable (MIT or Apache-2.0; its
licence text is not shipped yet: see MetalUI-THIRD-PARTY-NOTICES.md).
NOTICE

step "Writing $DIST/$NAME.tar.gz"
mkdir -p "$DIST"
mv "$FOLDER" "$WORK/$NAME"
tar -C "$WORK" -czf "$DIST/$NAME.tar.gz" "$NAME"
printf '%s\n' "$DIST/$NAME.tar.gz"
