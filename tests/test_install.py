"""Tests for install.sh and tv uninstall, in a scratch home directory.

TVBOX_SOURCE points the installer at this checkout instead of GitHub."""
import os
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
         "TV_CONFIG": str(home / ".config/tv/config")}
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
def test_builds_mac_app(home):
    install(home)
    app = home / "Applications/Terminal Values.app"
    assert (app / "Contents/Resources/Scripts/main.scpt").exists()
    xattrs = subprocess.run(["xattr", str(app)], capture_output=True, text=True).stdout
    assert "com.apple.quarantine" not in xattrs


def test_uninstall_removes_line_app_and_tv(home, tmp_path):
    install(home)
    bin_ = tmp_path / "fakebin"
    bin_.mkdir()
    (bin_ / "docker").symlink_to(FAKE)
    log = tmp_path / "log"
    r = subprocess.run(["sh", str(home / ".local/bin/tv"), "uninstall", "--yes-keep-state"],
                       env=env(home, path=f"{bin_}:/usr/bin:/bin", FAKE_LOG=str(log),
                               FAKE_STATE="running"),
                       capture_output=True, text=True)
    assert r.returncode == 0, r.stdout + r.stderr
    assert not (home / ".local/bin/tv").exists()
    assert MARK not in (home / ".zshrc").read_text()
    assert not (home / "Applications/Terminal Values.app").exists()
    calls = log.read_text()
    assert '"rm"' in calls and "tvbox" in calls
    assert '"volume", "rm"' not in calls.replace("  ", " ")


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
