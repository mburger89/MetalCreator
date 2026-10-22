#!/bin/bash
# Builds dist/MetalCreator-<version>-linux-<arch>.AppImage from the Linux tarball (scripts/package-linux.sh), so both carry the
# same staged tree: the executable with RUNPATH $ORIGIN/lib, lib/, MetalUISDLShaders, share/ and the licences. The tarball's
# folder becomes usr/metalcreator in an AppDir that also holds AppRun, the desktop entry and the icon (the same files the tarball
# installs, from packaging/linux), and appimagetool packs the AppDir. install.sh is left out: an AppImage is not unpacked.
#
# usage: scripts/package-appimage.sh [tarball]    default: the newest dist/MetalCreator-*-linux-<arch>.tar.gz
#   METALCREATOR_DIST_DIR   where the tarball is and the AppImage is written (default: <repo>/dist).
#   METALCREATOR_TOOLS      where the downloaded tools are kept (default: <dist>/tools).
# appimagetool and the AppImage runtime are third-party tools fetched here, at build time, pinned by version and sha256. They are no
# dependency of MetalCreator: nothing links them, and only the runtime ends up in the output (it is the AppImage's first bytes).
# appimagetool itself is not shipped. The runtime is MIT licensed (type2-runtime's LICENSE) but is a static binary that contains
# musl libc (MIT), libfuse3 (LGPL-2.1), squashfuse (BSD-2-Clause), libzstd (BSD), zlib and mimalloc (MIT): their licences are in
# packaging/appimage/licenses and go into the AppImage with a section of NOTICE.txt (from type2-runtime's LICENSE and Makefile at
# the pinned tag; mimalloc is linked per the Makefile but missing from its LICENSE list). The build needs no FUSE: appimagetool is itself an AppImage and runs with --appimage-extract-and-run.
# Needs curl, sha256sum and `file` (appimagetool refuses to run without it).
set -euo pipefail

# Bumping a version means changing its hashes; AppImageRecipeTests checks that every one is present and 64 hex digits.
APPIMAGETOOL_VERSION=1.9.1
APPIMAGETOOL_SHA256_x86_64=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
APPIMAGETOOL_SHA256_aarch64=f0837e7448a0c1e4e650a93bb3e85802546e60654ef287576f46c71c126a9158
RUNTIME_TAG=20251108
RUNTIME_SHA256_x86_64=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d
RUNTIME_SHA256_aarch64=00cbdfcf917cc6c0ff6d3347d59e0ca1f7f45a6df1a428a0d6d8a78664d87444

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${METALCREATOR_DIST_DIR:-$ROOT/dist}"
TOOLS="${METALCREATOR_TOOLS:-$DIST/tools}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

step() { printf '==> %s\n' "$*"; }
fail() { printf 'package-appimage: %s\n' "$*" >&2; exit 1; }

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64|aarch64) ;;
    arm64) ARCH=aarch64 ;;
    *) fail "no appimagetool for $ARCH" ;;
esac
for tool in curl sha256sum file; do command -v "$tool" >/dev/null || fail "$tool is needed"; done

TARBALL="${1:-$(ls -t "$DIST"/MetalCreator-*-linux-"$ARCH".tar.gz 2>/dev/null | head -n 1)}"
[ -f "$TARBALL" ] || fail "no tarball: run scripts/package-linux.sh first"
NAME="$(basename "$TARBALL" .tar.gz)"

# Downloads $1 to $2 unless $2 is already there, and requires its sha256 to be $3.
fetch() {
    [ -f "$2" ] || curl -fsSL --retry 3 -o "$2" "$1"
    printf '%s  %s\n' "$3" "$2" | sha256sum -c --quiet - || { rm -f "$2"; fail "$1 is not the pinned file (sha256 $3)"; }
}

step "Fetching appimagetool $APPIMAGETOOL_VERSION and the runtime $RUNTIME_TAG (pinned)"
mkdir -p "$TOOLS"
tool_hash="APPIMAGETOOL_SHA256_$ARCH"
runtime_hash="RUNTIME_SHA256_$ARCH"
fetch "https://github.com/AppImage/appimagetool/releases/download/$APPIMAGETOOL_VERSION/appimagetool-$ARCH.AppImage" \
    "$TOOLS/appimagetool-$APPIMAGETOOL_VERSION-$ARCH.AppImage" "${!tool_hash}"
fetch "https://github.com/AppImage/type2-runtime/releases/download/$RUNTIME_TAG/runtime-$ARCH" \
    "$TOOLS/runtime-$RUNTIME_TAG-$ARCH" "${!runtime_hash}"
chmod +x "$TOOLS/appimagetool-$APPIMAGETOOL_VERSION-$ARCH.AppImage"

step "Assembling the AppDir from $NAME"
APPDIR="$WORK/AppDir"
mkdir -p "$APPDIR/usr"
tar -xzf "$TARBALL" -C "$WORK"
mv "$WORK/$NAME" "$APPDIR/usr/metalcreator"
[ -x "$APPDIR/usr/metalcreator/MetalCreator" ] || fail "the tarball has no MetalCreator executable"
rm "$APPDIR/usr/metalcreator/install.sh"
DOC="$APPDIR/usr/metalcreator/share/doc/metalcreator"
[ -s "$DOC/NOTICE.txt" ] || fail "the tarball has no share/doc/metalcreator/NOTICE.txt"
mkdir -p "$DOC/AppImage-runtime"
for f in type2-runtime-LICENSE.txt musl-COPYRIGHT.txt libfuse-LGPL2.txt squashfuse-LICENSE.txt zstd-LICENSE.txt zlib-LICENSE.txt mimalloc-LICENSE.txt; do
    [ -s "$ROOT/packaging/appimage/licenses/$f" ] || fail "packaging/appimage/licenses/$f is missing"
    cp "$ROOT/packaging/appimage/licenses/$f" "$DOC/AppImage-runtime/"
done
cat >> "$DOC/NOTICE.txt" <<NOTICE

AppImage runtime (the first bytes of this file; type2-runtime $RUNTIME_TAG)
  Source:   https://github.com/AppImage/type2-runtime, tag $RUNTIME_TAG. Its LICENSE is MIT (AppImage-runtime/type2-runtime-LICENSE.txt).
  The runtime is a static executable. Its LICENSE and Makefile say it contains, and its texts are in AppImage-runtime/:
    musl libc (MIT)                      musl-COPYRIGHT.txt
    libfuse3 3.15.0 (LGPL-2.1)           libfuse-LGPL2.txt; source https://github.com/libfuse/libfuse, tag fuse-3.15.0, with the
                                         patch in type2-runtime's patches/libfuse
    squashfuse 0.5.2 (BSD-2-Clause)      squashfuse-LICENSE.txt
    libzstd (BSD)                        zstd-LICENSE.txt
    zlib (zlib licence)                  zlib-LICENSE.txt
    mimalloc (MIT)                       mimalloc-LICENSE.txt
  Relinking libfuse: the runtime is a separate file that you can replace. Extract the AppImage (--appimage-extract), take the
  squashfs image from it, and prepend a runtime you built from type2-runtime's source (with a modified libfuse if you like); an
  AppImage is that runtime followed by the squashfs.
NOTICE
ID=com.metalcreator.MetalCreator
cp "$ROOT/packaging/appimage/AppRun" "$APPDIR/AppRun"
chmod +x "$APPDIR/AppRun"
cp "$ROOT/packaging/linux/$ID.desktop" "$ROOT/packaging/linux/$ID.png" "$APPDIR/"
ln -s "$ID.png" "$APPDIR/.DirIcon"

step "Writing $DIST/$NAME.AppImage"
rm -f "$DIST/$NAME.AppImage"
ARCH="$ARCH" "$TOOLS/appimagetool-$APPIMAGETOOL_VERSION-$ARCH.AppImage" --appimage-extract-and-run \
    --runtime-file "$TOOLS/runtime-$RUNTIME_TAG-$ARCH" "$APPDIR" "$DIST/$NAME.AppImage" >"$WORK/appimagetool.log" 2>&1 \
    || { cat "$WORK/appimagetool.log" >&2; fail "appimagetool failed"; }
[ -x "$DIST/$NAME.AppImage" ] || fail "appimagetool wrote no executable AppImage"
printf '%s\n' "$DIST/$NAME.AppImage"
