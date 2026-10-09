#!/bin/bash
# Builds dist/MetalCreator.app: a release build of MetalCreatorApp with the OpenCascade libraries it links (and theirs,
# from Homebrew) copied into Contents/Frameworks and re-pointed there, MetalUI's resource bundles in Contents/Resources,
# an Info.plist written by the app itself (`--info-plist`), signed inside-out, then checked by scripts/verify-app.sh.
# The app is assembled in a temporary folder and replaces dist/MetalCreator.app only once it has passed, so a failed
# run leaves the previous app alone.
# Design: docs/superpowers/specs/2026-10-09-packaging-design.md.
#
# usage: scripts/package-app.sh
#   METALCREATOR_SIGN_IDENTITY  codesign identity; "-" (the default) signs ad hoc. A "Developer ID Application: …"
#                               identity also turns on the hardened runtime and a secure timestamp.
#   METALCREATOR_DIST_DIR       where the .app is written (default: <repo>/dist).
# Needs only the Xcode command-line tools and Homebrew's opencascade (the build links it).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="${METALCREATOR_DIST_DIR:-$ROOT/dist}"
IDENTITY="${METALCREATOR_SIGN_IDENTITY:--}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/MetalCreator.app"
CONTENTS="$APP/Contents"
FRAMEWORKS="$CONTENTS/Frameworks"

step() { printf '==> %s\n' "$*"; }
fail() { printf 'package-app: %s\n' "$*" >&2; exit 1; }

# Dependencies the system provides; everything else is bundled.
is_system() { case "$1" in /usr/lib/*|/System/*) return 0 ;; *) return 1 ;; esac; }

# The install names a Mach-O file links, without its own id.
linked_libraries() {
    local own
    own="$(otool -D "$1" | sed -n '2p')"
    otool -L "$1" | sed -n '2,$p' | sed -E 's/^[[:space:]]+//; s/ \(compatibility version.*$//' \
        | while IFS= read -r name; do [ "$name" = "$own" ] || printf '%s\n' "$name"; done
}

# The LC_RPATH entries of a Mach-O file.
rpaths() { otool -l "$1" | awk '$1 == "cmd" && $2 == "LC_RPATH" { want = 1 } want && $1 == "path" { print $2; want = 0 }'; }

# The minimum macOS a Mach-O file was built for (LC_BUILD_VERSION). awk reads to the end: an early exit could kill otool
# with SIGPIPE, which pipefail and set -e would turn into a silent stop.
minimum_os() { otool -l "$1" | awk '$1 == "cmd" { want = ($2 == "LC_BUILD_VERSION") } want && $1 == "minos" && !found { v = $2; found = 1 } END { print v }'; }

# Resolves install name $1, linked by the file at original path $2, to a file on disk (Homebrew's, before copying).
resolve() {
    local name="$1" loader_dir candidate rpath
    loader_dir="$(dirname "$2")"
    case "$name" in
        @rpath/*)
            while IFS= read -r rpath; do
                rpath="${rpath/@loader_path/$loader_dir}"
                rpath="${rpath/@executable_path/$(dirname "$BINARY")}"
                candidate="$rpath/${name#@rpath/}"
                if [ -f "$candidate" ]; then printf '%s\n' "$candidate"; return; fi
            done < <(rpaths "$2"; [ "$2" = "$BINARY" ] || rpaths "$BINARY")
            ;;
        @loader_path/*) candidate="$loader_dir/${name#@loader_path/}"; [ -f "$candidate" ] && printf '%s\n' "$candidate" && return ;;
        @executable_path/*) candidate="$(dirname "$BINARY")/${name#@executable_path/}"; [ -f "$candidate" ] && printf '%s\n' "$candidate" && return ;;
        /*) [ -f "$name" ] && printf '%s\n' "$name" && return ;;
    esac
    fail "can't find $name, linked by $2"
}

step "Building MetalCreatorApp (release)"
swift build --package-path "$ROOT" -c release --product MetalCreatorApp
BIN_DIR="$(swift build --package-path "$ROOT" -c release --product MetalCreatorApp --show-bin-path)"
BINARY="$BIN_DIR/MetalCreatorApp"

step "Assembling MetalCreator.app"
mkdir -p "$CONTENTS/MacOS" "$FRAMEWORKS" "$CONTENTS/Resources"
cp "$BINARY" "$CONTENTS/MacOS/MetalCreator"
for bundle in "$BIN_DIR"/*.bundle; do
    if [ -d "$bundle" ]; then cp -R "$bundle" "$CONTENTS/Resources/"; fi
done

step "Copying the non-system libraries it links, transitively"
# $WORK/seen holds "<file name> <real path>" per bundled library; $WORK/queue the files still to scan.
: > "$WORK/seen"
printf '%s\n' "$BINARY" > "$WORK/queue"
while [ -s "$WORK/queue" ]; do
    file="$(head -n 1 "$WORK/queue")"
    sed -i '' '1d' "$WORK/queue"
    while IFS= read -r name; do
        is_system "$name" && continue
        library="$(basename "$name")"
        source="$(resolve "$name" "$file")"
        real="$(realpath "$source")"
        known="$(awk -v library="$library" '$1 == library { print $2 }' "$WORK/seen")"
        if [ -n "$known" ]; then
            [ "$known" = "$real" ] || fail "two different libraries are both named $library: $known and $real"
            continue
        fi
        printf '%s %s\n' "$library" "$real" >> "$WORK/seen"
        cp "$real" "$FRAMEWORKS/$library"
        chmod u+w "$FRAMEWORKS/$library"
        printf '%s\n' "$source" >> "$WORK/queue"
    done < <(linked_libraries "$file")
done
printf '    %s libraries\n' "$(wc -l < "$WORK/seen" | tr -d ' ')"

step "Copying their licences into Contents/Resources/Licenses"
# Each library comes from a Homebrew keg, <prefix>/Cellar/<formula>/<version>; its licence files sit at the keg's top
# level or in share/doc/<formula>.
for keg in $(awk '{ print $2 }' "$WORK/seen" | sed -nE 's#^(.*/Cellar/[^/]+/[^/]+)/.*#\1#p' | sort -u); do
    formula="$(basename "$(dirname "$keg")")"
    mkdir -p "$CONTENTS/Resources/Licenses/$formula"
    find "$keg" "$keg/share/doc/$formula" -maxdepth 1 -type f \
        \( -iname 'LICENSE*' -o -iname 'COPYING*' -o -iname '*EXCEPTION*' \) \
        -exec cp {} "$CONTENTS/Resources/Licenses/$formula/" \; 2> /dev/null || true
    [ -n "$(ls -A "$CONTENTS/Resources/Licenses/$formula")" ] || fail "found no licence file for $formula in $keg"
    printf '    %s: %s\n' "$formula" "$(ls "$CONTENTS/Resources/Licenses/$formula" | tr '\n' ' ')"
done
[ "$(awk '{ print $2 }' "$WORK/seen" | grep -vc '/Cellar/' || true)" -eq 0 ] \
    || fail "a bundled library isn't from a Homebrew keg, so its licence is unknown: $(awk '{ print $2 }' "$WORK/seen" | grep -v '/Cellar/' | head -n 1)"

step "Pointing every link at Contents/Frameworks"
repoint() {
    local file="$1" name
    local args=()
    codesign --remove-signature "$file"
    while IFS= read -r name; do
        is_system "$name" || args+=(-change "$name" "@rpath/$(basename "$name")")
    done < <(linked_libraries "$file")
    while IFS= read -r name; do args+=(-delete_rpath "$name"); done < <(rpaths "$file")
    install_name_tool ${args[@]+"${args[@]}"} "${@:2}" "$file"
}
for library in "$FRAMEWORKS"/*.dylib; do
    repoint "$library" -id "@rpath/$(basename "$library")"
done
repoint "$CONTENTS/MacOS/MetalCreator" -add_rpath "@executable_path/../Frameworks"

step "Writing Info.plist"
minimum="$(for file in "$CONTENTS/MacOS/MetalCreator" "$FRAMEWORKS"/*.dylib; do minimum_os "$file"; done \
    | sort -t. -k1,1n -k2,2n -k3,3n | tail -n 1)"
declared="$(minimum_os "$CONTENTS/MacOS/MetalCreator")"
[ "$minimum" = "$declared" ] \
    || printf '    note: the bundled libraries need macOS %s; Package.swift asks for %s\n' "$minimum" "$declared"
"$BINARY" --info-plist "$minimum" > "$CONTENTS/Info.plist"

step "Signing ($([ "$IDENTITY" = "-" ] && echo "ad hoc" || echo "$IDENTITY"))"
sign_options=(--force --sign "$IDENTITY")
[ "$IDENTITY" = "-" ] || sign_options+=(--options runtime --timestamp)
for library in "$FRAMEWORKS"/*.dylib; do
    codesign "${sign_options[@]}" "$library"
done
codesign "${sign_options[@]}" "$APP"

"$ROOT/scripts/verify-app.sh" "$APP"

mkdir -p "$DIST"
rm -rf "$DIST/MetalCreator.app"
mv "$APP" "$DIST/MetalCreator.app"
step "Wrote $(cd "$DIST" && pwd -P)/MetalCreator.app"
