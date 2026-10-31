#!/bin/sh
# Start the box (tvbox:dev, from image_test.sh) with a scratch folder and
# volume, and check what it sets up inside. Needs no tailnet: joining is
# checked only as far as refusing a missing or bogus key.
cd "$(dirname "$0")/.." || exit 1
RT=${TV_RUNTIME:-container}
IMAGE=tvbox:dev
NAME=tvbox-test
VOL=tvbox-test-state
fails=0
ok()   { echo "ok: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
U=$(id -u) G=$(id -g)
inbox() { $RT exec -u "$U:$G" "$NAME" "$@"; }

FOLDER=$(mktemp -d "${TMPDIR:-/tmp}/tvbox-folder.XXXXXX")
cleanup() {
    $RT rm -f "$NAME" >/dev/null 2>&1 || $RT stop "$NAME" >/dev/null 2>&1
    $RT rm "$NAME" >/dev/null 2>&1
    $RT volume rm "$VOL" >/dev/null 2>&1
    rm -rf "$FOLDER"
}
cleanup >/dev/null 2>&1; FOLDER=$(mktemp -d "${TMPDIR:-/tmp}/tvbox-folder.XXXXXX")
trap cleanup EXIT

# A real device ID for "tvhome", so Syncthing accepts it.
TVHOME_ID=$($RT run --rm --entrypoint sh "$IMAGE" -c \
    'syncthing generate --home=/tmp/st >/dev/null 2>&1; syncthing serve --home=/tmp/st --device-id' 2>/dev/null | tail -1)

[ "$RT" = container ] && $RT volume create "$VOL" >/dev/null 2>&1
$RT run -d --name "$NAME" -v "$FOLDER:/home/tv/terminalvalues" -v "$VOL:/state" \
    -e "TV_UID=$U" -e "TV_GID=$G" -e TV_LOGIN=tvtest \
    -e "TV_NAME=Test Member" -e TV_EMAIL=tvtest@example.org \
    -e TVHOME_HOST=tvhome.example-tailnet.ts.net \
    -e "TVHOME_SYNCTHING_ID=$TVHOME_ID" "$IMAGE" >/dev/null || { fail "the box doesn't start"; exit 1; }

# Wait for Syncthing to have written its config.
i=0
until inbox test -s /state/syncthing/config.xml 2>/dev/null && inbox grep -q terminalvalues /state/syncthing/config.xml 2>/dev/null; do
    i=$((i + 1)); [ $i -gt 60 ] && break; sleep 1
done

if inbox pgrep -f 'tailscaled.*userspace-networking' >/dev/null; then
    ok "tailscaled runs in userspace mode"
else
    fail "tailscaled isn't running in userspace mode"
fi
if inbox bash -c 'echo > /dev/tcp/127.0.0.1/1055' 2>/dev/null; then
    ok "the SOCKS5 proxy is listening on 127.0.0.1:1055"
else
    fail "nothing listens on 127.0.0.1:1055"
fi
if [ "$(inbox stat -c %u /state/syncthing)" = "$U" ] && [ "$(inbox stat -c %u /state/home)" = "$U" ]; then
    ok "the state belongs to the member's uid"
else
    fail "/state isn't the member's"
fi

conf=$(inbox cat /state/syncthing/config.xml 2>/dev/null)
for want in '<globalAnnounceEnabled>false' '<localAnnounceEnabled>false' '<relaysEnabled>false' \
            'path="/home/tv/terminalvalues"' 'ignorePerms="true"' 'rescanIntervalS="15"' \
            "id=\"$TVHOME_ID\"" '<address>tcp://tvhome.example-tailnet.ts.net:22000</address>'; do
    case $conf in
        *"$want"*) ok "Syncthing config has $want" ;;
        *) fail "Syncthing config lacks $want" ;;
    esac
done
if inbox sh -c 'tr "\0" "\n" < /proc/$(pgrep -f "syncthing serve" | head -1)/environ' 2>/dev/null |
   grep -qx 'all_proxy=socks5://127.0.0.1:1055'; then
    ok "Syncthing dials out through the box's proxy"
else
    fail "Syncthing's environment lacks all_proxy=socks5://127.0.0.1:1055"
fi
if cmp -s "$FOLDER/.stignore" box/stignore; then
    ok "the folder's .stignore carries only TV's data"
else
    fail "the folder's .stignore isn't box/stignore"
fi
if inbox grep -q 'ProxyCommand tailscale nc %h %p' /state/home/.ssh/config 2>/dev/null &&
   inbox grep -q 'User tvtest' /state/home/.ssh/config &&
   inbox grep -q 'LogLevel ERROR' /state/home/.ssh/config; then
    ok "ssh reaches tvhome through Tailscale, as the member"
else
    fail "the ssh config is missing or wrong"
fi

# Syncthing itself ignores agents' instructions in a data directory, in any
# case, but shares an ordinary document there.
mkdir -p "$FOLDER/doc/.claude"
echo note > "$FOLDER/doc/ok.md"; echo x > "$FOLDER/doc/CLAUDE.md"; echo x > "$FOLDER/doc/agents.MD"
echo '{}' > "$FOLDER/doc/.mcp.json"; echo x > "$FOLDER/doc/.claude/settings.json"
ignored=$(inbox sh -c '
    key=$(sed -n "s:.*<apikey>\(.*\)</apikey>.*:\1:p" /state/syncthing/config.xml)
    api() { curl -s -H "X-API-Key: $key" "$@"; }
    api -X POST "http://127.0.0.1:8384/rest/db/scan?folder=terminalvalues" >/dev/null
    i=0; until api "http://127.0.0.1:8384/rest/db/file?folder=terminalvalues&file=doc/ok.md" |
        grep -q "\"ignored\": false" || [ $i -gt 30 ]; do i=$((i + 1)); sleep 1; done
    for f in doc/ok.md doc/CLAUDE.md doc/agents.MD doc/.mcp.json doc/.claude/settings.json; do
        if api "http://127.0.0.1:8384/rest/db/file?folder=terminalvalues&file=$f" | grep -q "\"ignored\": false"
        then printf "%s=shared " "$f"; else printf "%s=not " "$f"; fi
    done' 2>/dev/null)
if [ "$ignored" = "doc/ok.md=shared doc/CLAUDE.md=not doc/agents.MD=not doc/.mcp.json=not doc/.claude/settings.json=not " ]; then
    ok "Syncthing shares doc/ok.md but not agents' files"
else
    fail "Syncthing's view of agents' files: $ignored"
fi
# Every script in the box parses (dash is pickier than bash: an apostrophe
# in ${VAR:?message} broke tvbox-catch-up).
for f in $(inbox sh -c 'ls /usr/local/bin/tvbox-*'); do
    # With the shell its first line names (tvbox-catch-up is bash).
    sh_=$(inbox head -1 "$f" | sed 's/^#! *//; s/ .*//')
    if inbox "$sh_" -n "$f" 2>/dev/null; then ok "$f parses"; else fail "$f doesn't parse: $(inbox "$sh_" -n "$f" 2>&1)"; fi
done
# ssh reads its config from the passwd entry's home, not $HOME, so the
# member's entry must say /state/home: for a uid from their computer (a
# Mac), and for root (rootless Podman, found in the Linux run: ssh read
# /root/.ssh, missed the ProxyCommand and hung).
for uid in 0 4321; do
    home=$($RT run --rm --entrypoint sh -e "TV_UID=$uid" -e "TV_GID=$uid" "$IMAGE" \
        -c 'tvbox-user && getent passwd '"$uid"' | cut -d: -f6' 2>/dev/null)
    if [ "$home" = /state/home ]; then ok "uid $uid's home is /state/home"
    else fail "uid $uid's home is '$home', not /state/home"; fi
done
# ssh needs a passwd entry for the uid it runs as, and commits need a name.
if inbox ssh -G tvhome 2>/dev/null | grep -qx 'user tvtest'; then
    ok "ssh runs as the member's uid"
else
    fail "ssh can't run as uid $U: $(inbox ssh -G tvhome 2>&1 | head -1)"
fi
if [ "$(inbox git config --global user.name)" = "Test Member" ] &&
   [ "$(inbox git config --global user.email)" = tvtest@example.org ]; then
    ok "git commits carry the member's name and email"
else
    fail "git's user.name/user.email aren't the member's"
fi

out=$($RT exec -i -u "$U:$G" "$NAME" tvbox-join tvtest </dev/null 2>&1)
if [ $? -ne 0 ] && printf '%s' "$out" | grep -q 'no auth key'; then
    ok "join refuses no key"
else
    fail "join with no key said: $out"
fi
out=$(echo tskey-auth-bogus | $RT exec -i -u "$U:$G" "$NAME" tvbox-join tvtest 2>&1)
if [ $? -ne 0 ] && ! inbox test -e /state/home/.passage/identities &&
   ! inbox grep -rqs tskey-auth-bogus /state /tmp; then
    ok "join with a bad key fails, makes no age key, and leaves no copy of the key"
else
    fail "join with a bad key: $out"
fi
# import-key keeps an existing key unless told to replace it (a second
# computer brings in the member's saved key over the one join made).
inbox sh -c 'age-keygen -o /tmp/k1 2>/dev/null; age-keygen -o /tmp/k2 2>/dev/null'
inbox sh -c 'tvbox-import-key < /tmp/k1' >/dev/null 2>&1
if ! inbox sh -c 'tvbox-import-key < /tmp/k2' >/dev/null 2>&1 &&
   inbox sh -c 'tvbox-import-key --replace < /tmp/k2' >/dev/null 2>&1 &&
   [ "$(inbox sh -c 'age-keygen -y /state/home/.passage/identities')" = "$(inbox sh -c 'age-keygen -y /tmp/k2')" ]; then
    ok "import-key replaces a key only with --replace"
else
    fail "import-key --replace doesn't behave"
fi

# The three lines Danny needs: tvbox-identity gives the Syncthing ID and the
# public half of the age key (one exists by now, from import-key above).
me=$(inbox tvbox-identity 2>/dev/null)
if printf '%s' "$me" | jq -e '(.syncthing | test("^([A-Z2-7]{7}-){7}[A-Z2-7]{7}$")) and (.age | startswith("age1"))' >/dev/null 2>&1; then
    ok "tvbox-identity gives the Syncthing ID and the age key's public half"
else
    fail "tvbox-identity said: $me"
fi
# The check-up's box half runs, answers every check, and with no tailnet here
# says so rather than hanging.
doc=$(inbox tvbox-doctor --json 2>/dev/null)
if [ "$(printf '%s' "$doc" | jq -r '[.results[].id] | join(" ")' 2>/dev/null)" = \
     "tailnet route tvhome-ssh tvhome-pages tvhome-sync sync-errors folder stignore age-key recipient disk-box" ]; then
    ok "tvbox-doctor gives all eleven of the box's checks"
else
    fail "tvbox-doctor said: $doc"
fi
# Stopping the box stops its daemons properly, so tvhome sees Syncthing
# hang up instead of waiting on a dead connection.
$RT stop "$NAME" >/dev/null 2>&1
if $RT logs "$NAME" 2>&1 | grep -q "Signal 15 received; exiting"; then
    ok "stopping the box stops Syncthing cleanly"
else
    fail "Syncthing was killed, not stopped, when the box stopped"
fi
exit "$fails"
