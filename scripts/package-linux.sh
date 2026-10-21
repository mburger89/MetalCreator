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
VERSION="$("$BINARY" --version | sed -E 's/^MetalCreator ([0-9][^ ]*) .*/\1/')"
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
cp "$OCCT"/share/licenses/* "$DOC/"
cp "$METALUI/THIRD-PARTY-NOTICES.md" "$DOC/MetalUI-THIRD-PARTY-NOTICES.md"
for f in CStbImage/LICENSE CFreeType/FTL.TXT CFreeType/LICENSE.TXT CHarfBuzz/COPYING CUnibreak/LICENCE CSheenBidi/LICENSE; do
    cp "$METALUI/Sources/$f" "$DOC/$(dirname "$f")-$(basename "$f")"
done

step "Writing $DIST/$NAME.tar.gz"
mkdir -p "$DIST"
mv "$FOLDER" "$WORK/$NAME"
tar -C "$WORK" -czf "$DIST/$NAME.tar.gz" "$NAME"
printf '%s\n' "$DIST/$NAME.tar.gz"
