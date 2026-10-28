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
    else curl -fsSL "$BASE/$1" -o "$2"; fi
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
    echo "Made $app: click it to start the box and open the TV folder."
fi

echo
echo "Next: tv join (with the login name you picked and the key Danny sent you)."
