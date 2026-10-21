#!/bin/bash
# Registers this MetalCreator folder with the desktop for the current user: a launcher entry that opens .mcgraph files
# (Exec=… %F hands the file manager's files to the app), the .mcgraph MIME type and the icon the entry names. Run it from the
# extracted folder; run it again after moving the folder. `install.sh --remove` undoes it.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd -P)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
ID=com.metalcreator.MetalCreator
DESKTOP="$DATA/applications/$ID.desktop"
MIME="$DATA/mime/packages/$ID.xml"
ICON="$DATA/icons/hicolor/256x256/apps/$ID.png"

refresh() {
    if command -v update-mime-database >/dev/null 2>&1; then update-mime-database "$DATA/mime"; fi
    if command -v update-desktop-database >/dev/null 2>&1; then update-desktop-database "$DATA/applications"; fi
    # Only where the user's hicolor folder is a complete theme (it has an index.theme); otherwise the lookup finds the file itself.
    if command -v gtk-update-icon-cache >/dev/null 2>&1 && [ -f "$DATA/icons/hicolor/index.theme" ]; then
        gtk-update-icon-cache -q -t "$DATA/icons/hicolor" || true
    fi
}

case "${1:-}" in
    "")
        # A desktop entry's Exec line has its own quoting rules; a path with spaces is quoted, and these characters are refused.
        case "$HERE" in
            *[\"\$\\\`\|\&]*)
                echo "install.sh: the folder's path contains one of \" \$ \\ \` | & which a launcher entry can't hold; move it." >&2
                exit 1
                ;;
        esac
        mkdir -p "$DATA/applications" "$DATA/mime/packages" "$DATA/icons/hicolor/256x256/apps"
        # The folder's own path replaces the bare command, so the entry works wherever the folder is. In a quoted Exec argument a
        # percent sign starts a field code, so the path's own are written %%.
        EXEC_PATH="${HERE//%/%%}"
        while IFS= read -r line; do
            case "$line" in
                "Exec=MetalCreator "*) printf 'Exec="%s/MetalCreator" %s\n' "$EXEC_PATH" "${line#Exec=MetalCreator }" ;;
                *) printf '%s\n' "$line" ;;
            esac
        done < "$HERE/share/applications/$ID.desktop" > "$DESKTOP"
        cp "$HERE/share/mime/packages/$ID.xml" "$MIME"
        cp "$HERE/share/icons/hicolor/256x256/apps/$ID.png" "$ICON"
        refresh
        echo "Registered $HERE/MetalCreator for .mcgraph files."
        ;;
    --remove)
        rm -f "$DESKTOP" "$MIME" "$ICON"
        refresh
        echo "Removed MetalCreator's launcher entry, icon and .mcgraph type."
        ;;
    *)
        echo "usage: install.sh [--remove]" >&2
        exit 64
        ;;
esac
