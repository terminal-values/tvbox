# tvbox

`tv` runs one container on a Terminal Values member's computer, holding
everything TV needs (a private network connection, Syncthing, git, a
shared password store), so the member's computer itself only gets a
container runtime and this script.

```console
$ tv status
On TV's tailnet.
Up to date with tvhome (214 files).
$ tv catch-up
Code and instructions changed on tvhome since you last caught up:
  1a2b3c4 Sam: Add a receipts importer
 bin/import-receipts | 42 ++++++++++++++++++++++++++
Apply them? [y/N] y
Caught up with tvhome (1a2b3c4 Add a receipts importer).
```

The TV folder stays an ordinary folder (`~/Documents/terminalvalues`) that the member
opens in their own apps and points their agent at. The box mounts it and
does the syncing, the git and the secrets.

## Install

You need a container runtime first: Apple's
[`container`](https://github.com/apple/container/releases) on a Mac
(macOS 26 or later, Apple silicon), or `sudo apt install podman` on
Debian or Ubuntu. Docker works too. Then:

```sh
curl -fsSL https://raw.githubusercontent.com/terminal-values/tvbox/main/install.sh | sh
```

That puts `tv` in `~/.local/bin` (adding it to your PATH only if it isn't
there, and saying so) and, on a Mac, builds `~/Applications/Terminal
Values.app`. No sudo. Then it runs `tv join`, which asks for your login
name and email and waits for you to copy the invitation you were sent: one
line, `tvjoin:TAILNET:SYNCTHING-ID:KEY`. On a Mac it picks that up from the
clipboard, so the key is never pasted or shown.

`tv uninstall` takes all of it away again, asking before it deletes the
box's storage (which holds your age key).

## Commands

```
tv start / stop        the box; documents sync only while it runs
tv status              on the tailnet? syncing?
tv catch-up            code and secrets up to date, code changes shown first
tv push                commits and the secrets store to tvhome
tv git ... / tv passage ... / tv run CMD ...   in the box, in the folder
tv pages [PAGE]        TV's internal pages, via 127.0.0.1:8484 (or the next free port)
tv shell               a shell in the box
tv export-key FILE     save a copy of your age key (readable only by you)
tv import-key          bring one in (--replace to swap out a new one)
tv update              a newer box, showing tvbox's commits since yours first
tv folder / move DIR    where the TV folder is; put it somewhere else
```

## How it works

- Tailscale runs in userspace mode inside the box, logged in with a
  single-use key tagged for that member. No TUN device, no system
  extension, no Tailscale account. Everything the box says to tvhome goes
  through Tailscale's local SOCKS5 proxy.
- Syncthing in the box talks only to tvhome, through that proxy: no
  discovery, no relays. It carries TV's documents; git carries code.
- The box starts as root only long enough to hand its storage (a volume,
  `tv-state`, at `/state`) to your uid, then runs everything as you, so
  files in the folder are yours.
- The image is pinned by digest. `tv update` lists the commits between the
  image you have and the newest one, and asks before switching, since the
  box holds your key.
- The Mac app is AppleScript compiled on your own Mac with `osacompile`,
  so it's never downloaded and needs no notarisation.

None of this names TV's tailnet or tvhome's address: each member's
invitation does.

## Limits

This is built for one small organisation's setup, a tvhome machine on its
own tailnet, and probably isn't much use as it stands to anyone else.
Windows isn't supported. On a Mac, Apple's `container` passes on no
file-change notices, so edits wait for a rescan (every 15 seconds).
Documents don't sync while the box is stopped, and nothing starts it at
login.

## Development

```sh
make test        # tv and the installer, against a fake runtime (pytest via uv)
make box-test    # builds the image and checks what starts inside it
```

Both runtimes are worth testing: `TV_RUNTIME=docker make box-test`.

MIT licence.
