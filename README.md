# tvbox

`tv` runs one container on a Terminal Values member's computer, holding
everything TV needs (a private network connection, Syncthing, git, a
shared password store), so the member's computer itself only gets a
container runtime and this script.

```console
$ tv status
On TV's tailnet.
Up to date with TVhome (214 files).
$ tv catch-up
Code and instructions changed on TVhome since you last caught up:
  1a2b3c4 Sam: Add a receipts importer
 bin/import-receipts | 42 ++++++++++++++++++++++++++
Apply them? [y/N] y
Caught up with TVhome (1a2b3c4 Add a receipts importer).
```

The TVhome Folder stays an ordinary folder (`~/Documents/terminalvalues`) that the member
opens in their own apps and points their agent at. The box mounts it and
does the syncing, the git and the secrets.

## Install

**On a Mac** (macOS 26 or later, Apple silicon only): download Terminal
Values.app from the [latest release](https://github.com/terminal-values/tvbox/releases/latest),
drag it to Applications and open it. It walks you through the rest without
Terminal: Apple's [`container`](https://github.com/apple/container) (the
one thing installed for the whole Mac, with your password), the invitation
you were sent (one line, `tvjoin:TAILNET:SYNCTHING-ID:LOGIN:KEY`, which
holds the login you agreed with Danny; it's picked up from the clipboard so
the key is never pasted or shown), saving
your key, and the folder filling. After that it lives in the menu bar, and
puts its own `tv` in `~/.local/bin` for terminals and agents.

**On Linux** (or a Mac, from a terminal): `sudo apt install podman` on
Debian or Ubuntu (Docker works too), then

```sh
curl -fsSL https://raw.githubusercontent.com/terminal-values/tvbox/main/install.sh | sh
```

That puts `tv` in `~/.local/bin` (adding it to your PATH only if it isn't
there, and saying so), no sudo, and runs `tv join`, which asks for your
name and email and then for the invitation.

`tv uninstall` takes all of it away again, asking before it deletes the
box's storage (which holds your age key).

## Commands

```
tv start / stop        the box; documents sync only while it runs
tv status [--json]     on the tailnet? syncing?
tv stats / identity / changes / doctor   CPU and memory; the lines Danny needs;
                       what catch-up would bring; a check-up (--json for the app)
tv catch-up            code and secrets up to date, code changes shown first
tv push                commits and the secrets store to TVhome
tv phone               pair your phone with TVhome: a QR code to scan (--json for the app)
tv claude-rc           Claude Code's Remote Control in the folder, for claude.ai/code
                       or the Claude app (needs Claude Code and a paid Claude plan)
tv git ... / tv passage ... / tv run CMD ...   in the box, in the folder
tv pages [PAGE]        TVhome Pages, via 127.0.0.1:8484
tv link PATH           a TVhome link for a file in the folder, to share in TV Signal (on a Mac, also copies it)
tv open LINK           open your own copy of a TVhome link's file (--print: just its path)
tv shell               a shell in the box
tv export-key FILE     save a copy of your age key (readable only by you)
tv import-key          bring one in (--replace to swap out a new one)
tv update              a newer box, showing tvbox's commits since yours first
                       (with the Mac app installed, the app updates itself and the box together)
tv folder / move DIR    where the TVhome Folder is; put it somewhere else
```

The box's port is always 8484. Setting `PORT=` in tv's config overrides
it, for two boxes on one computer; TVhome links won't open on that
computer then, and `tv doctor` says so.

## How it works

- Tailscale runs in userspace mode inside the box, logged in with a
  single-use key tagged for that member. No TUN device, no system
  extension, no Tailscale account. Everything the box says to TVhome goes
  through Tailscale's local SOCKS5 proxy.
- Syncthing in the box talks only to TVhome, through that proxy: no
  discovery, no relays. It carries TV's documents; git carries code.
- The box starts as root only long enough to hand its storage (a volume,
  `tv-state`, at `/state`) to your uid, then runs everything as you, so
  files in the folder are yours.
- The image is pinned by digest. `tv update` lists the commits between the
  image you have and the newest one, and asks before switching, since the
  box holds your key.
- The Mac app (`mac/`, SwiftUI) is a face on `tv`: it bundles it and runs
  it for everything, so there's one implementation of joining, catching up
  and updating. It's signed with a Developer ID and notarized, and updates
  itself with Sparkle; each release pins the box image built from the same
  commit, and moves the box to it after updating.

None of this names TV's tailnet or TVhome's address: each member's
invitation does.

## Limits

This is built for one small organisation's setup, a TVhome machine on its
own tailnet, and probably isn't much use as it stands to anyone else.
Windows isn't supported. On a Mac, Apple's `container` passes on no
file-change notices, so edits wait for a rescan (every 15 seconds).
Documents don't sync while the box is stopped; the Mac app starts it when
it opens and stops it when it quits, and opens at login only if you ask.

## Development

```sh
make test        # tv and the installer, against a fake runtime (pytest via uv)
make box-test    # builds the image and checks what starts inside it
make app-test    # the Mac app's tests (Xcode, and brew install xcodegen)
make app         # builds it, unsigned, into mac/build
```

Releases are made on the Mac that holds the signing keys, not on GitHub,
which holds none of them: push the commit and its tag (`v0.1.0`), check out
the tag, then `make app-release VERSION=0.1.0` (`mac/scripts/release.sh`
lists the variables it needs) and `make app-publish VERSION=0.1.0`.

Both runtimes are worth testing: `TV_RUNTIME=docker make box-test`.

MIT licence.
