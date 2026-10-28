#!/bin/sh
# Installs tv, Terminal Values' box command, for this user only:
#   curl -fsSL https://raw.githubusercontent.com/terminal-values/tvbox/main/install.sh | sh
#
# It puts tv in ~/.local/bin, adds that to your PATH in your shell's
# startup file if it isn't there already (and says so), and on a Mac makes
# ~/Applications/Terminal Values.app. Nothing else on this computer
# changes, and no sudo. `tv uninstall` undoes all of it.
set -eu
BASE=https://raw.githubusercontent.com/terminal-values/tvbox/main
MARK="# added by the tvbox installer"
BIN=$HOME/.local/bin

fetch() {  # fetch PATH-IN-REPO DEST
    if [ -n "${TVBOX_SOURCE:-}" ]; then cp "$TVBOX_SOURCE/$1" "$2"
    else curl -fsSL "$BASE/$(printf '%s' "$1" | sed 's/ /%20/g')" -o "$2"; fi
}

mkdir -p "$BIN"
fetch tv "$BIN/tv.new"
chmod 755 "$BIN/tv.new"
mv -f "$BIN/tv.new" "$BIN/tv"
echo "Installed tv in $BIN."

case ":$PATH:" in
    *":$BIN:"*) ;;
    *)
        case $(basename "${SHELL:-sh}") in
            zsh) rc=$HOME/.zshrc ;;
            bash) rc=$HOME/.bashrc ;;
            *) rc=$HOME/.profile ;;
        esac
        if ! grep -qF "$MARK" "$rc" 2>/dev/null; then
            printf '%s\n' "export PATH=\"\$HOME/.local/bin:\$PATH\"  $MARK" >> "$rc"
            echo "Added ~/.local/bin to your PATH, in $rc (one line, marked; tv uninstall removes it)."
            echo "Open a new terminal window for it to take effect."
        fi ;;
esac

if [ "$(uname)" = Darwin ]; then
    app="$HOME/Applications/Terminal Values.app"
    script=$(mktemp "${TMPDIR:-/tmp}/tvapp.XXXXXX")
    fetch "mac/Terminal Values.applescript" "$script"
    mkdir -p "$HOME/Applications"
    rm -rf "$app"
    osacompile -o "$app" "$script"
    rm -f "$script"
    # TV's icon, made with the Mac's own sips and iconutil; then sign the app
    # again (ad hoc, as osacompile did), since its contents changed.
    work=$(mktemp -d "${TMPDIR:-/tmp}/tvicon.XXXXXX")
    fetch mac/icon.png "$work/icon.png"
    mkdir "$work/tv.iconset"
    for n in 16 32 128 256 512; do
        sips -z $n $n "$work/icon.png" --out "$work/tv.iconset/icon_${n}x${n}.png" >/dev/null
        sips -z $((n * 2)) $((n * 2)) "$work/icon.png" --out "$work/tv.iconset/icon_${n}x${n}@2x.png" >/dev/null
    done
    iconutil -c icns "$work/tv.iconset" -o "$app/Contents/Resources/applet.icns"
    rm -rf "$work"
    codesign --force --sign - "$app" 2>/dev/null
    touch "$app"
    echo "Made $app: click it to start the box and open the TV folder."
fi

# Straight on to joining, at the terminal (the installer's own input is the
# script, so tv join reads from /dev/tty). Not if this computer has already
# joined, or there's no terminal to ask at.
if [ -z "${TVBOX_NO_JOIN:-}" ] && ! "$BIN/tv" folder >/dev/null 2>&1 && { : </dev/tty; } 2>/dev/null; then
    echo
    echo "Now to join Terminal Values from this computer."
    "$BIN/tv" join </dev/tty
else
    echo
    echo "Next: tv join, with the login name you picked and the invitation Danny sent you."
fi
