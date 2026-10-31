"""Tests for install.sh and tv uninstall, in a scratch home directory.

TVBOX_SOURCE points the installer at this checkout instead of GitHub."""
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
FAKE = Path(__file__).resolve().parent / "fakeruntime"
MARK = "# added by the tvbox installer"


@pytest.fixture
def home(tmp_path):
    h = tmp_path / "home"
    h.mkdir()
    return h


def env(home, shell="/bin/zsh", path="/usr/bin:/bin", **kw):
    e = {"HOME": str(home), "SHELL": shell, "PATH": path, "TVBOX_SOURCE": str(ROOT),
         "TV_CONFIG": str(home / ".config/tv/config"), "TVBOX_NO_JOIN": "1"}
    e.update(kw)
    return e


def install(home, **kw):
    return subprocess.run(["sh", str(ROOT / "install.sh")], env=env(home, **kw),
                          capture_output=True, text=True)


def test_installs_tv(home):
    r = install(home)
    assert r.returncode == 0, r.stdout + r.stderr
    tv = home / ".local/bin/tv"
    assert tv.exists() and os.stat(tv).st_mode & 0o777 == 0o755


def test_adds_path_once_for_zsh(home):
    r = install(home)
    assert ".zshrc" in r.stdout
    install(home)
    lines = [l for l in (home / ".zshrc").read_text().splitlines() if MARK in l]
    assert lines == ['export PATH="$HOME/.local/bin:$PATH"  ' + MARK]


def test_bash_uses_bashrc(home):
    install(home, shell="/bin/bash")
    assert MARK in (home / ".bashrc").read_text()
    assert not (home / ".zshrc").exists()


def test_leaves_path_alone_when_present(home):
    install(home, path=f"{home}/.local/bin:/usr/bin:/bin")
    assert not (home / ".zshrc").exists()


@pytest.mark.skipif(sys.platform != "darwin", reason="the app is for macOS")
def test_tv_folder_prints_the_folder(home):
    cfg = home / ".config/tv"
    cfg.mkdir(parents=True)
    (cfg / "config").write_text(f"FOLDER='{home}/Terminal Values'\nLOGIN='sam'\n")
    r = subprocess.run(["sh", str(ROOT / "tv"), "folder"], env=env(home),
                       capture_output=True, text=True)
    assert r.stdout.strip() == f"{home}/Terminal Values"


def test_fetches_from_github_with_urls_curl_accepts(home, tmp_path):
    """Without TVBOX_SOURCE it fetches by URL; a space in one makes curl refuse it."""
    bin_ = tmp_path / "fakebin"
    bin_.mkdir()
    log = tmp_path / "urls"
    curl = bin_ / "curl"
    curl.write_text(f"""#!/bin/sh
for a; do case $a in https://*) url=$a ;; esac; done
for a; do case $prev in -o) out=$a ;; esac; prev=$a; done
echo "$url" >> {log}
case $url in *" "*) exit 3 ;; esac
path=$(printf '%s' "${{url#https://raw.githubusercontent.com/terminal-values/tvbox/main/}}" | sed 's/%20/ /g')
cp "{ROOT}/$path" "$out"
""")
    curl.chmod(0o755)
    e = env(home, path=f"{bin_}:/usr/bin:/bin")
    del e["TVBOX_SOURCE"]
    r = subprocess.run(["sh", str(ROOT / "install.sh")], env=e, capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    assert all(" " not in u for u in log.read_text().splitlines())


def test_installer_goes_on_to_join():
    """After installing, the installer runs tv join at the terminal (not in tests)."""
    text = (ROOT / "install.sh").read_text()
    assert '"$BIN/tv" join </dev/tty' in text and "TVBOX_NO_JOIN" in text


def test_next_step_names_tv_by_its_full_path_until_the_path_has_it(home):
    # Found in the outsider test: "Next: tv join" in a terminal where tv
    # wasn't on the PATH yet gave "command not found".
    r = install(home)
    assert f"Next: {home}/.local/bin/tv join" in r.stdout
    r = install(home, path=f"{home}/.local/bin:/usr/bin:/bin")
    assert "Next: tv join" in r.stdout


def test_without_a_terminal_it_finishes_and_says_what_is_next(home):
    # Found in the Linux run: with no terminal (an agent installing for
    # someone), the check for /dev/tty made sh exit 2 without a word.
    e = env(home)
    del e["TVBOX_NO_JOIN"]
    # dash is Debian's sh, and the one that exits; a Mac has it too.
    shell = shutil.which("dash") or "sh"
    r = subprocess.run([shell, str(ROOT / "install.sh")], env=e, capture_output=True, text=True,
                       stdin=subprocess.DEVNULL, start_new_session=True)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "tv join" in r.stdout


def test_reinstalling_on_a_joined_computer_doesnt_say_join(home):
    # Rerunning the installer is how the Mac app gets rebuilt after an update.
    cfg = home / ".config/tv"
    cfg.mkdir(parents=True)
    (cfg / "config").write_text(f"FOLDER='{home}/terminalvalues'\nLOGIN='sam'\n")
    r = install(home)
    assert r.returncode == 0, r.stdout + r.stderr
    assert "tv join" not in r.stdout
    assert "already joined" in r.stdout


def test_installer_on_a_mac_builds_no_app(home):
    # The Swift app, downloaded, replaces the one the installer used to build.
    r = install(home)
    assert r.returncode == 0, r.stdout + r.stderr
    assert not (home / "Applications/Terminal Values.app").exists()
    if platform.system() == "Darwin":
        assert "github.com/terminal-values/tvbox/releases" in r.stdout


def run_uninstall(home, tmp_path, **env_extra):
    bin_ = tmp_path / "fakebin"
    bin_.mkdir(exist_ok=True)
    if not (bin_ / "docker").exists():
        (bin_ / "docker").symlink_to(FAKE)
    log = tmp_path / "log"
    return subprocess.run(["sh", str(home / ".local/bin/tv"), "uninstall", "--yes-keep-state"],
                          env=env(home, path=f"{bin_}:/usr/bin:/bin", FAKE_LOG=str(log),
                                  FAKE_STATE="running", **env_extra),
                          capture_output=True, text=True), log


def test_uninstall_removes_line_tv_and_an_applescript_app(home, tmp_path):
    install(home)
    old = home / "Applications/Terminal Values.app/Contents/Resources/Scripts"
    old.mkdir(parents=True)
    (old / "main.scpt").write_text("compiled")
    r, log = run_uninstall(home, tmp_path)
    assert r.returncode == 0, r.stdout + r.stderr
    assert not (home / ".local/bin/tv").exists()
    assert MARK not in (home / ".zshrc").read_text()
    assert not (home / "Applications/Terminal Values.app").exists()
    calls = log.read_text()
    assert '"rm"' in calls and "tvbox" in calls
    assert '"volume", "rm"' not in calls.replace("  ", " ")


def test_uninstall_removes_only_an_applescript_app(home, tmp_path):
    install(home)
    decoy = home / "Applications/Terminal Values.app/Contents/MacOS"
    decoy.mkdir(parents=True)
    r, _ = run_uninstall(home, tmp_path)
    assert r.returncode == 0, r.stdout + r.stderr
    assert decoy.exists()


def test_uninstall_spares_the_app_in_applications(home, tmp_path):
    install(home)
    apps = tmp_path / "Applications"
    (apps / "Terminal Values.app/Contents/MacOS").mkdir(parents=True)
    r, _ = run_uninstall(home, tmp_path, TVBOX_SYSTEM_APPS=str(apps))
    assert r.returncode == 0, r.stdout + r.stderr
    assert (apps / "Terminal Values.app").exists()
    assert "Trash" in r.stdout


def test_uninstall_removes_a_symlinked_tv(home, tmp_path):
    install(home)
    target = tmp_path / "app-tv"
    target.write_text((home / ".local/bin/tv").read_text())
    target.chmod(0o755)
    (home / ".local/bin/tv").unlink()
    (home / ".local/bin/tv").symlink_to(target)
    r = subprocess.run(["sh", str(target), "uninstall", "--yes-keep-state"],
                       env=env(home, path="/usr/bin:/bin"), capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    assert not (home / ".local/bin/tv").is_symlink() and not (home / ".local/bin/tv").exists()
    assert target.exists()
