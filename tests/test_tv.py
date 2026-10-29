"""Tests for tv, the host-side command, against a fake container runtime.

tv runs with a PATH holding only the fake runtimes it's given and the
ordinary tools it needs, so what's installed on the test machine doesn't
leak in."""
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
STID = "MVOEDBP-QTCGNI7-Q6ZZW22-HCGLNE5-5EQZ4NS-5USUULU-D7EIS4I-J2Q3EQX"
INVITE = f"tvjoin:example-tailnet.ts.net:{STID}:tskey-auth-x-y\n"
TV = ROOT / "tv"
FAKE = Path(__file__).resolve().parent / "fakeruntime"
# dash, Debian's sh and the strictest about POSIX, when this machine has it.
SH = shutil.which("dash") or "sh"
TOOLS = ["sh", "env", "python3", "id", "mkdir", "cat", "sed", "grep", "ls",
         "uname", "mv", "rm", "rmdir", "tr", "dirname", "head", "chmod", "basename"]


@pytest.fixture
def box(tmp_path):
    return Box(tmp_path)


class Box:
    def __init__(self, tmp):
        self.tmp = tmp
        self.home = tmp / "home"
        self.home.mkdir()
        self.bin = tmp / "bin"
        self.bin.mkdir()
        for tool in TOOLS:
            real = shutil.which(tool)
            if real:
                (self.bin / tool).symlink_to(real)
        # Linux unless a test says otherwise, whatever this machine is.
        (self.bin / "uname").unlink(missing_ok=True)
        (self.bin / "uname").write_text('#!/bin/sh\necho "${FAKE_UNAME:-Linux}"\n')
        (self.bin / "uname").chmod(0o755)
        self.log = tmp / "log"
        self.log.touch()
        self.config = tmp / "config"

    def runtimes(self, *names):
        for n in names:
            (self.bin / n).symlink_to(FAKE)

    def configure(self, **kw):
        kw.setdefault("FOLDER", str(self.home / "terminalvalues"))
        kw.setdefault("IMAGE", "ghcr.io/terminal-values/tvbox@sha256:abc")
        kw.setdefault("LOGIN", "sam")
        kw.setdefault("NAME", "Sam Smith")
        kw.setdefault("EMAIL", "sam@example.org")
        kw.setdefault("TAILNET", "example-tailnet.ts.net")
        kw.setdefault("TVHOME_ID", STID)
        self.config.write_text("".join(f"{k}='{v}'\n" for k, v in kw.items()))

    def tv(self, *args, input="", **env):
        e = {"PATH": str(self.bin), "HOME": str(self.home), "TV_CONFIG": str(self.config),
             "FAKE_LOG": str(self.log), "SHELL": "/bin/zsh"}
        e.update(env)
        return subprocess.run([SH, str(TV), *args], input=input, capture_output=True,
                              text=True, env=e)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def call(self, verb):
        """The first logged call whose verb (first argument) is verb."""
        return next(c for c in self.calls() if len(c) > 1 and c[1] == verb)


def test_detects_runtime_in_order(box):
    box.runtimes("docker")
    box.configure()
    box.tv("start")
    assert box.calls()[0][0] == "docker"


def test_prefers_apples_container(box):
    box.runtimes("container", "docker")
    box.configure()
    box.tv("start")
    assert {c[0] for c in box.calls()} == {"container"}


def test_no_runtime_at_all(box):
    box.configure()
    r = box.tv("start")
    assert r.returncode == 4
    assert "container runtime" in r.stdout + r.stderr


@pytest.mark.parametrize("runtime,hint", [("container", "container system start"),
                                          ("docker", "Docker Desktop")])
def test_runtime_not_running(box, runtime, hint):
    box.runtimes(runtime)
    box.configure()
    r = box.tv("start", FAKE_DOWN="1")
    assert r.returncode == 4
    assert hint in r.stdout + r.stderr


def test_start_args_quote_spaces(box):
    box.runtimes("docker")
    folder = box.home / "Terminal Values"
    box.configure(FOLDER=str(folder))
    box.tv("start")
    run = box.call("run")
    assert f"{folder}:/home/tv/terminalvalues" in run
    assert "tv-state:/state" in run
    assert "127.0.0.1:8484:8484" in run
    assert "--name" in run and run[run.index("--name") + 1] == "tvbox"
    assert run[-1] == "ghcr.io/terminal-values/tvbox@sha256:abc"
    assert "TVHOME_HOST=tvhome.example-tailnet.ts.net" in run
    assert f"TVHOME_SYNCTHING_ID={STID}" in run
    assert "TV_NAME=Sam Smith" in run and "TV_EMAIL=sam@example.org" in run


def test_start_existing_box_starts_it(box):
    box.runtimes("docker")
    box.configure()
    box.tv("start", FAKE_STATE="stopped")
    assert box.call("start")[2] == "tvbox"
    assert not [c for c in box.calls() if c[1] == "run"]


def test_runs_as_host_user(box):
    box.runtimes("docker")
    box.configure()
    box.tv("start")
    run = box.call("run")
    assert f"TV_UID={os.getuid()}" in run and f"TV_GID={os.getgid()}" in run


def test_rootless_podman_is_root_inside(box):
    box.runtimes("podman")
    box.configure()
    box.tv("start")
    assert "TV_UID=0" in box.call("run")


def test_status_when_stopped(box):
    box.runtimes("docker")
    box.configure()
    r = box.tv("status", FAKE_STATE="stopped")
    assert r.returncode == 3
    assert "not running" in r.stdout and "not syncing" in r.stdout


def test_commands_need_a_running_box(box):
    box.runtimes("docker")
    box.configure()
    r = box.tv("push", FAKE_STATE="stopped")
    assert r.returncode == 3
    assert "tv start" in r.stdout + r.stderr


@pytest.mark.parametrize("args,inside", [
    (["catch-up"], ["tvbox-catch-up"]),
    (["push"], ["tvbox-push"]),
    (["git", "status", "--short"], ["git", "status", "--short"]),
    (["passage", "ls"], ["passage", "ls"]),
])
def test_commands_exec_in_box(box, args, inside):
    box.runtimes("docker")
    box.configure()
    box.tv(*args, FAKE_STATE="running")
    ex = box.call("exec")
    assert ex[-len(inside):] == inside
    assert ex[ex.index("-w") + 1] == "/home/tv/terminalvalues"
    assert ex[ex.index("-u") + 1] == f"{os.getuid()}:{os.getgid()}"
    assert "tvbox" in ex


def test_join_refuses_foreign_folder(box):
    box.runtimes("docker")
    folder = box.home / "stuff"
    folder.mkdir()
    (folder / "notes.txt").write_text("mine")
    r = box.tv("join", "--login", "sam", "--folder", str(folder), input=INVITE)
    assert r.returncode == 2
    assert "--adopt" in r.stdout + r.stderr
    assert not [c for c in box.calls() if c[1] == "run"]


def test_join_adopts_when_asked(box):
    box.runtimes("docker")
    folder = box.home / "stuff"
    folder.mkdir()
    (folder / "notes.txt").write_text("mine")
    r = box.tv("join", "--login", "sam", "--folder", str(folder), "--adopt",
               input=INVITE)
    assert r.returncode == 0, r.stdout + r.stderr
    assert f"{folder}:/home/tv/terminalvalues" in box.call("run")


def test_join_makes_a_missing_folder_and_writes_config(box):
    box.runtimes("docker")
    r = box.tv("join", "--login", "sam", input=INVITE)
    assert r.returncode == 0, r.stdout + r.stderr
    assert (box.home / "terminalvalues").is_dir()
    text = box.config.read_text()
    assert "LOGIN='sam'" in text and f"FOLDER='{box.home / 'terminalvalues'}'" in text
    assert "TAILNET='example-tailnet.ts.net'" in text and f"TVHOME_ID='{STID}'" in text
    assert "tskey" not in text
    assert "TVHOME_HOST=tvhome.example-tailnet.ts.net" in box.call("run")
    ex = box.call("exec")
    assert ex[-2:] == ["tvbox-join", "sam"] and "-i" in ex


def test_join_checks_the_login(box):
    box.runtimes("docker")
    r = box.tv("join", "--login", "Sam Smith", input=INVITE)
    assert r.returncode == 2
    assert not box.calls() or not [c for c in box.calls() if c[1] == "run"]


def test_export_key_refuses_a_terminal(box):
    box.runtimes("docker")
    box.configure()
    # Not a tty in tests, so it would export; check the guard is in the script.
    assert "[ -t 1 ]" in TV.read_text()


FAKECURL = Path(__file__).resolve().parent / "fakecurl"
OLD = "a" * 40
NEW = "b" * 40


def updatable(box, revision=OLD):
    box.runtimes("docker")
    (box.bin / "curl").symlink_to(FAKECURL)
    box.configure(IMAGE="ghcr.io/terminal-values/tvbox@sha256:old", REVISION=revision)


def test_update_shows_and_asks_yes(box):
    updatable(box)
    r = box.tv("update", input="y\n", FAKE_STATE="running")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "Make the box smaller" in r.stdout and "Fix tv status" in r.stdout
    assert "The commit this box is on" not in r.stdout
    text = box.config.read_text()
    assert "IMAGE='ghcr.io/terminal-values/tvbox@sha256:newdigest'" in text
    assert f"REVISION='{NEW}'" in text
    assert box.call("rm")[-1] == "tvbox"
    assert box.call("run")[-1] == "ghcr.io/terminal-values/tvbox@sha256:newdigest"


def test_update_no_leaves_everything(box):
    updatable(box)
    before = box.config.read_text()
    r = box.tv("update", input="n\n", FAKE_STATE="running")
    assert box.config.read_text() == before
    assert not [c for c in box.calls() if c[1] in ("rm", "run")]


def test_update_when_current(box):
    updatable(box, revision=NEW)
    r = box.tv("update", FAKE_STATE="running")
    assert r.returncode == 0
    assert "up to date" in r.stdout
    assert not [c for c in box.calls() if c[1] in ("rm", "run")]


@pytest.mark.parametrize("bad", ["tskey-auth-x-y\n", "tvjoin:example-tailnet.ts.net:tskey-auth-x\n", "\n"])
def test_join_wants_the_whole_invitation(box, bad):
    box.runtimes("docker")
    r = box.tv("join", "--login", "sam", input=bad)
    assert r.returncode == 2
    assert "invitation" in r.stdout + r.stderr
    assert not [c for c in box.calls() if c[1] == "run"]


def test_run_runs_any_command_in_the_box(box):
    box.runtimes("docker")
    box.configure()
    box.tv("run", "sh", "-c", "echo hi", FAKE_STATE="running")
    assert box.call("exec")[-3:] == ["sh", "-c", "echo hi"]


def test_join_takes_an_invitation_without_a_final_newline(box):
    """pbpaste | tv join gives no newline at the end."""
    box.runtimes("docker")
    r = box.tv("join", "--login", "sam", input=INVITE.rstrip("\n"))
    assert r.returncode == 0, r.stdout + r.stderr
    assert "TVHOME_HOST=tvhome.example-tailnet.ts.net" in box.call("run")


def test_join_asks_for_name_and_email_and_keeps_them(box):
    box.runtimes("docker")
    r = box.tv("join", "--login", "sam", "--name", "Sam Smith", "--email", "sam@example.org",
               input=INVITE)
    assert r.returncode == 0, r.stdout + r.stderr
    text = box.config.read_text()
    assert "NAME='Sam Smith'" in text and "EMAIL='sam@example.org'" in text


@pytest.mark.parametrize("setup,want", [
    ({"runtimes": [], "config": True, "env": {}}, "no-runtime"),
    ({"runtimes": ["container"], "config": True, "env": {"FAKE_DOWN": "1"}}, "runtime-stopped"),
    ({"runtimes": ["container"], "config": False, "env": {}}, "not-joined"),
    ({"runtimes": ["container"], "config": True, "env": {"FAKE_STATE": "absent"}}, "stopped"),
    ({"runtimes": ["container"], "config": True, "env": {"FAKE_STATE": "stopped"}}, "stopped"),
    ({"runtimes": ["container"], "config": True, "env": {"FAKE_STATE": "running"}}, "running"),
])
def test_check_says_where_things_stand(box, setup, want):
    """For the Mac app: one word, always exit 0."""
    box.runtimes(*setup["runtimes"])
    if setup["config"]:
        box.configure()
    r = box.tv("check", **setup["env"])
    assert r.returncode == 0
    assert r.stdout.strip() == want


@pytest.mark.parametrize("runtime,argv", [
    ("container", ["container", "system", "start", "--enable-kernel-install"]),
    ("podman", ["podman", "machine", "start"]),
])
def test_runtime_start(box, runtime, argv):
    box.runtimes(runtime)
    box.tv("runtime-start")
    assert argv in box.calls()


def clipboard(box, contents):
    """A fake pbpaste that gives each of contents in turn (the last one
    from then on), and a fake pbcopy that records what it's given."""
    clip = box.tmp / "clip"
    clip.write_text("\n".join(contents))
    count = box.tmp / "clipcount"
    count.write_text("0")
    (box.bin / "pbpaste").write_text(f"""#!/bin/sh
n=$(cat {count}); echo $((n + 1)) > {count}
total=$(wc -l < {clip}); total=$((total + 1))
[ $n -ge $total ] && n=$((total - 1))
sed -n "$((n + 1))p" {clip} | tr -d '\\n'
""")
    (box.bin / "pbcopy").write_text(f"#!/bin/sh\ncat > {box.tmp / 'copied'}; echo copied >> {box.tmp / 'pbcopy.log'}\n")
    for f in ("pbpaste", "pbcopy"):
        (box.bin / f).chmod(0o755)
    for tool in ("wc", "tr", "sleep"):
        if not (box.bin / tool).exists():
            (box.bin / tool).symlink_to(shutil.which(tool))


def test_join_waits_for_the_invitation_on_the_clipboard(box):
    box.runtimes("docker")
    clipboard(box, ["some other text", "tvjoin:not-a-whole-one", INVITE.strip()])
    r = box.tv("join", "--login", "sam", "--name", "Sam", "--email", "s@example.org",
               "--from-clipboard", TV_POLL="0")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "copy the invitation" in r.stdout
    assert "TVHOME_HOST=tvhome.example-tailnet.ts.net" in box.call("run")
    assert (box.tmp / "copied").read_text() == ""  # the clipboard is cleared after


def test_join_from_clipboard_never_prints_the_key(box):
    box.runtimes("docker")
    clipboard(box, [INVITE.strip()])
    r = box.tv("join", "--login", "sam", "--name", "Sam", "--email", "s@example.org",
               "--from-clipboard", TV_POLL="0")
    assert "tskey-auth-x-y" not in r.stdout + r.stderr


def test_join_checks_the_runtime_before_asking_anything(box):
    box.configure(FOLDER="", LOGIN="")
    r = box.tv("join")
    assert r.returncode == 4
    assert "container runtime" in r.stdout + r.stderr
    assert "login" not in r.stdout.lower() and "invitation" not in r.stdout.lower()


# --- found in the outsider test, 2026-10-28 ----------------------------------

def busy_ports(box, *ports):
    """A fake nc: something on this computer listens on these ports."""
    allowed = " ".join(str(p) for p in ports)
    (box.bin / "nc").write_text(f'#!/bin/sh\nfor a; do p=$a; done\nfor b in {allowed}; do [ "$p" = "$b" ] && exit 0; done\nexit 1\n')
    (box.bin / "nc").chmod(0o755)


def test_join_picks_a_free_port_and_keeps_it(box):
    box.runtimes("docker")
    busy_ports(box, 8484, 8485)
    r = box.tv("join", "--login", "sam", input=INVITE)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "127.0.0.1:8486:8484" in box.call("run")
    assert "PORT='8486'" in box.config.read_text()


def test_start_moves_a_stopped_box_off_a_taken_port(box):
    box.runtimes("docker")
    box.configure(PORT="8484")
    busy_ports(box, 8484)
    r = box.tv("start", FAKE_STATE="stopped")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "127.0.0.1:8485:8484" in box.call("run")
    assert "PORT='8485'" in box.config.read_text()
    assert "8485" in r.stdout


def test_a_config_without_port_uses_8484(box):
    box.runtimes("docker")
    box.configure()
    box.tv("start")
    assert "127.0.0.1:8484:8484" in box.call("run")


def test_a_failed_join_writes_no_config_and_says_to_retry(box):
    box.runtimes("docker")
    r = box.tv("join", "--login", "sam", input=INVITE, FAKE_RUN_FAILS="1")
    assert r.returncode != 0
    assert not box.config.exists()
    assert "tv join again" in r.stdout + r.stderr


def test_join_takes_back_a_folder_only_syncthing_has_touched(box):
    box.runtimes("docker")
    folder = box.home / "terminalvalues"
    (folder / ".stfolder").mkdir(parents=True)
    (folder / ".stignore").write_text("x\n")
    r = box.tv("join", "--login", "sam", input=INVITE)
    assert r.returncode == 0, r.stdout + r.stderr


def test_pages_opens_a_page_by_its_path(box):
    # Once www/ has a front page, a member's own page isn't in a listing.
    box.runtimes("docker")
    box.configure(PORT="8485")
    (box.bin / "open").write_text(f'#!/bin/sh\necho "$@" > {box.tmp}/opened\n')
    (box.bin / "open").chmod(0o755)
    r = box.tv("pages", "hello-sam.html", FAKE_STATE="running")
    assert r.returncode == 0, r.stdout + r.stderr
    assert (box.tmp / "opened").read_text().strip() == "http://127.0.0.1:8485/hello-sam.html"
    box.tv("pages", "/notes/a b.html", FAKE_STATE="running")
    assert (box.tmp / "opened").read_text().strip() == "http://127.0.0.1:8485/notes/a%20b.html"


def test_an_unknown_command_says_so_and_suggests(box):
    # `tv catchup` printed the whole help, with no word of what was wrong.
    r = box.tv("catchup")
    assert r.returncode == 2
    assert "tv catchup isn't a command" in r.stderr and "tv catch-up" in r.stderr
    assert "tv uninstall" not in r.stderr
    r = box.tv("frobnicate")
    assert "isn't a command" in r.stderr and "tv help" in r.stderr


def test_help_lines_up():
    import re
    text = subprocess.run([SH, str(TV), "help"], capture_output=True, text=True).stdout
    rows = [line for line in text.splitlines() if line.startswith("  tv ")]
    starts = set()
    for line in rows:
        m = re.match(r"  tv .*?\S {2,}(\S)", line)
        assert m, line
        starts.add(m.start(1))
    assert len(starts) == 1, starts


# --- where the folder goes, and moving it (2026-10-29) -----------------------

def fake_tool(box, name, script):
    (box.bin / name).write_text("#!/bin/sh\n" + script + "\n")
    (box.bin / name).chmod(0o755)


def test_join_on_a_mac_puts_the_folder_in_documents(box):
    box.runtimes("container")
    fake_tool(box, "defaults", "echo 0")
    r = box.tv("join", "--login", "sam", input=INVITE, FAKE_UNAME="Darwin")
    assert r.returncode == 0, r.stdout + r.stderr
    assert (box.home / "Documents" / "terminalvalues").is_dir()
    assert f"FOLDER='{box.home}/Documents/terminalvalues'" in box.config.read_text()
    assert f"{box.home}/Documents/terminalvalues" in r.stdout
    assert f"Your TV folder is {box.home}/Documents/terminalvalues.\n" in r.stdout


def test_join_keeps_out_of_documents_icloud_syncs(box):
    box.runtimes("container")
    fake_tool(box, "defaults", '[ "$3" = FXICloudDriveDocuments ] && echo 1')
    r = box.tv("join", "--login", "sam", input=INVITE, FAKE_UNAME="Darwin")
    assert r.returncode == 0, r.stdout + r.stderr
    assert f"FOLDER='{box.home}/terminalvalues'" in box.config.read_text()
    assert "iCloud" in r.stdout


def test_join_on_linux_uses_the_xdg_documents_dir(box):
    box.runtimes("podman")
    docs = box.home / "Dokumente"
    docs.mkdir()
    fake_tool(box, "xdg-user-dir", f'[ "$1" = DOCUMENTS ] && echo {docs}')
    r = box.tv("join", "--login", "sam", input=INVITE)
    assert r.returncode == 0, r.stdout + r.stderr
    assert f"FOLDER='{docs}/terminalvalues'" in box.config.read_text()


def test_join_on_linux_without_documents_uses_home(box):
    box.runtimes("podman")
    fake_tool(box, "xdg-user-dir", f"echo {box.home}")
    r = box.tv("join", "--login", "sam", input=INVITE)
    assert f"FOLDER='{box.home}/terminalvalues'" in box.config.read_text()


def test_move_takes_the_folder_and_remakes_the_box(box):
    box.runtimes("docker")
    old, new = box.home / "terminalvalues", box.home / "Documents" / "tv"
    (old / "doc").mkdir(parents=True)
    (old / "doc" / "a.md").write_text("hi")
    box.configure(FOLDER=str(old))
    r = box.tv("move", str(new), FAKE_STATE="running")
    assert r.returncode == 0, r.stdout + r.stderr
    assert (new / "doc" / "a.md").read_text() == "hi" and not old.exists()
    assert f"FOLDER='{new}'" in box.config.read_text()
    verbs = [c[1] for c in box.calls() if len(c) > 1]
    assert verbs.index("stop") < verbs.index("rm") < verbs.index("run")
    assert f"{new}:/home/tv/terminalvalues" in box.call("run")


def test_move_into_an_empty_folder_and_leaves_a_stopped_box_stopped(box):
    box.runtimes("docker")
    old, new = box.home / "terminalvalues", box.home / "elsewhere"
    old.mkdir()
    (old / "x").write_text("x")
    new.mkdir()
    box.configure(FOLDER=str(old))
    r = box.tv("move", str(new), FAKE_STATE="stopped")
    assert r.returncode == 0, r.stdout + r.stderr
    assert (new / "x").exists()
    assert not [c for c in box.calls() if len(c) > 1 and c[1] == "run"]


@pytest.mark.parametrize("dest", ["full", "inside"])
def test_move_refuses_a_full_folder_or_one_inside_itself(box, dest):
    box.runtimes("docker")
    old = box.home / "terminalvalues"
    old.mkdir()
    (old / "x").write_text("x")
    target = old / "sub" if dest == "inside" else box.home / "full"
    if dest == "full":
        target.mkdir()
        (target / "y").write_text("y")
    box.configure(FOLDER=str(old))
    r = box.tv("move", str(target), FAKE_STATE="stopped")
    assert r.returncode == 2
    assert (old / "x").exists() and f"FOLDER='{old}'" in box.config.read_text()
    assert "isn't a command" not in r.stderr


def test_move_takes_a_relative_path(box, tmp_path):
    box.runtimes("docker")
    old = box.home / "terminalvalues"
    old.mkdir()
    box.configure(FOLDER=str(old))
    e = {"PATH": str(box.bin), "HOME": str(box.home), "TV_CONFIG": str(box.config),
         "FAKE_LOG": str(box.log), "FAKE_STATE": "stopped"}
    r = subprocess.run([SH, str(TV), "move", "Documents/tv"], cwd=box.home, env=e,
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    assert f"FOLDER='{box.home}/Documents/tv'" in box.config.read_text()


@pytest.mark.parametrize("unbuilt,digest,revision", [
    ("", "newdigest", NEW), ("1", "olderdigest", "d" * 40)])
def test_join_pins_the_newest_published_box(box, unbuilt, digest, revision):
    # Found in the Linux run: joining while the newest commit's image was
    # still building left the box unpinned, with no version recorded.
    box.runtimes("podman")
    (box.bin / "curl").symlink_to(FAKECURL)
    r = box.tv("join", "--login", "sam", input=INVITE, FAKE_UNBUILT=unbuilt)
    assert r.returncode == 0, r.stdout + r.stderr
    text = box.config.read_text()
    assert f"IMAGE='ghcr.io/terminal-values/tvbox@sha256:{digest}'" in text
    assert f"REVISION='{revision}'" in text


def test_joining_again_keeps_the_folder_it_has(box):
    # The final review: a second tv join (a new invitation, say) on a computer
    # whose folder is elsewhere made an empty one in Documents and mounted it.
    box.runtimes("podman")
    elsewhere = box.home / "Private" / "terminalvalues"
    (elsewhere / "doc").mkdir(parents=True)
    (elsewhere / "doc" / "a.md").write_text("hi")
    # No .git yet: a member who hasn't caught up. It's still TV's folder.
    (box.home / "Documents").mkdir()
    box.configure(FOLDER=str(elsewhere))
    r = box.tv("join", "--login", "sam", input=INVITE)
    assert r.returncode == 0, r.stdout + r.stderr
    assert f"FOLDER='{elsewhere}'" in box.config.read_text()
    assert f"{elsewhere}:/home/tv/terminalvalues" in box.call("run")
    assert not (box.home / "Documents" / "terminalvalues").exists()
