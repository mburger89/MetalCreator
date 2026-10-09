#!/bin/bash
# Checks a packaged MetalCreator.app (scripts/package-app.sh runs it last; run it again on a copy you moved):
#   1. Info.plist is well formed and names the executable;
#   2. the signature verifies, deep and strict;
#   3. no Mach-O file in the bundle links or searches Homebrew (/opt/homebrew, /usr/local), and every @rpath library
#      it links is in Contents/Frameworks;
#   4. LSMinimumSystemVersion is no older than any bundled binary's minimum macOS;
#   5. `MetalCreator --self-test` passes with the environment emptied (no DYLD_* variables) and Homebrew's directories
#      unreadable (sandbox-exec), and dyld loads nothing from outside the bundle and the system.
# usage: scripts/verify-app.sh [path/to/MetalCreator.app]   (default: <repo>/dist/MetalCreator.app)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/MetalCreator.app}"
[ -d "$APP" ] || { printf 'verify-app: FAILED: no app at %s\n' "$APP" >&2; exit 1; }
# Absolute and without symlinks, as dyld reports the paths it loads.
APP="$(cd "$APP" && pwd -P)"
CONTENTS="$APP/Contents"
PLIST="$CONTENTS/Info.plist"
NO_HOMEBREW='(version 1) (allow default) (deny file-read* (subpath "/opt/homebrew") (subpath "/usr/local"))'

step() { printf '==> verify: %s\n' "$*"; }
fail() { printf 'verify-app: FAILED: %s\n' "$*" >&2; exit 1; }

# The minimum macOS a Mach-O file was built for (LC_BUILD_VERSION). awk reads to the end: an early exit could kill otool
# with SIGPIPE, which pipefail and set -e would turn into a silent stop.
minimum_os() { otool -l "$1" | awk '$1 == "cmd" { want = ($2 == "LC_BUILD_VERSION") } want && $1 == "minos" && !found { v = $2; found = 1 } END { print v }'; }
# A macOS version as one comparable number, so 27, 27.0 and 27.0.0 are equal.
version_number() { printf '%s\n' "$1" | awk -F. '{ printf "%d\n", $1 * 1000000 + $2 * 1000 + $3 }'; }

step "Info.plist"
plutil -lint "$PLIST" > /dev/null || fail "Info.plist is not a valid property list"
executable="$(plutil -extract CFBundleExecutable raw "$PLIST")"
[ -x "$CONTENTS/MacOS/$executable" ] || fail "CFBundleExecutable $executable is not in Contents/MacOS"

step "signature"
codesign --verify --deep --strict "$APP" || fail "codesign --verify --deep --strict rejects the bundle"
codesign -dv "$APP" 2>&1 | grep -E '^(Identifier|Signature|Authority|TeamIdentifier)=' | sed 's/^/    /'

step "notices"
for notice in MetalUI/THIRD-PARTY-NOTICES.md MetalUI/stb_image-LICENSE; do
    [ -f "$CONTENTS/Resources/Licenses/$notice" ] || fail "Contents/Resources/Licenses/$notice is missing"
done

step "links"
minimum="$(plutil -extract LSMinimumSystemVersion raw "$PLIST")"
count=0
while IFS= read -r -d '' file; do
    file -b "$file" | grep -q 'Mach-O' || continue
    count=$((count + 1))
    if otool -L "$file" | grep -E '/opt/homebrew|/usr/local' > /dev/null; then
        fail "$file links a Homebrew library: $(otool -L "$file" | grep -E '/opt/homebrew|/usr/local' | head -n 1)"
    fi
    if otool -l "$file" | grep -E '^ +path (/opt/homebrew|/usr/local)' > /dev/null; then
        fail "$file searches a Homebrew directory (LC_RPATH)"
    fi
    for name in $(otool -L "$file" | sed -n '2,$p' | awk '{ print $1 }' | grep '^@rpath/' || true); do
        [ -f "$CONTENTS/Frameworks/${name#@rpath/}" ] || fail "$file links $name, which is not in Contents/Frameworks"
    done
    needs="$(minimum_os "$file")"
    [ "$(version_number "$needs")" -le "$(version_number "$minimum")" ] \
        || fail "$file needs macOS $needs, newer than LSMinimumSystemVersion $minimum"
done < <(find "$CONTENTS" -type f -print0)
printf '    %s Mach-O files, none linking Homebrew; LSMinimumSystemVersion %s\n' "$count" "$minimum"

step "self-test without Homebrew"
if sandbox-exec -p "$NO_HOMEBREW" /bin/ls /opt/homebrew > /dev/null 2>&1; then
    fail "sandbox-exec did not block /opt/homebrew, so this check would prove nothing"
fi
log="$(mktemp)"
trap 'rm -f "$log"' EXIT
if ! env -i HOME="$HOME" PATH=/usr/bin:/bin sandbox-exec -p "$NO_HOMEBREW" \
    /usr/bin/env DYLD_PRINT_LIBRARIES=1 "$CONTENTS/MacOS/$executable" --self-test > "$log" 2>&1; then
    sed 's/^/    /' "$log" >&2
    fail "the self-test failed"
fi
grep -v '^dyld\[' "$log" | sed 's/^/    /'
loaded="$(grep -c '^dyld\[[0-9]*\]: <' "$log" || true)"
outside="$(grep '^dyld\[[0-9]*\]: <' "$log" | sed -E 's/^dyld\[[0-9]+\]: <[^>]*> //' \
    | grep -v -e "^$CONTENTS/" -e '^/usr/lib/' -e '^/System/' || true)"
[ -z "$outside" ] || fail "dyld loaded libraries from outside the bundle: $outside"
if [ "$loaded" -eq 0 ]; then
    printf '    (dyld printed no load list: the hardened runtime ignores DYLD_PRINT_LIBRARIES; the links check stands)\n'
else
    printf '    dyld loaded %s images, all from the bundle or the system\n' "$loaded"
fi
step "passed: $APP"
