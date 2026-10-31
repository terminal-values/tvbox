#!/bin/sh
# Installs tv, Terminal Values' box command, for this user only:
#   curl -fsSL https://raw.githubusercontent.com/terminal-values/tvbox/main/install.sh | sh
#
# It puts tv in ~/.local/bin and adds that to your PATH in your shell's
# startup file if it isn't there already (and says so). Nothing else on this
# computer changes, and no sudo. `tv uninstall` undoes all of it. On a Mac,
# Terminal Values.app (from the releases page) does the same with clicks.
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
    echo "On a Mac, Terminal Values.app does all this with clicks, and keeps tv up to date:"
    echo "  https://github.com/terminal-values/tvbox/releases/latest"
fi

# Straight on to joining, at the terminal (the installer's own input is the
# script, so tv join reads from /dev/tty). Not if this computer has already
# joined, or there's no terminal to ask at.
if [ -z "${TVBOX_NO_JOIN:-}" ] && ! "$BIN/tv" folder >/dev/null 2>&1 && (: </dev/tty) 2>/dev/null; then
    echo
    echo "Now to join Terminal Values from this computer."
    "$BIN/tv" join </dev/tty
else
    echo
    # This terminal's PATH lacks ~/.local/bin if the installer just added it.
    case ":$PATH:" in *":$BIN:"*) tv=tv ;; *) tv=$BIN/tv ;; esac
    if "$BIN/tv" folder >/dev/null 2>&1; then
        echo "This computer has already joined TV: $tv status says how the box is."
    else
        echo "Next: $tv join, with the login name you picked and the invitation Danny sent you."
    fi
fi
