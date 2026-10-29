"""box/tvbox-status, run on the host against a fake tailscale and a fake
Syncthing API (curl), since what it says depends only on their answers."""
import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TVHOME = "GGGGGGG-GGGGGGG-GGGGGGG-GGGGGGG-GGGGGGG-GGGGGGG-GGGGGGG-GGGGGGG"

FAKE_CURL = """#!/bin/sh
# Answers Syncthing's REST API from $FAKE_API/<path with / and ? turned to _>.
for a; do url=$a; done
p=${url#*/rest/}; p=${p%%\\?*}
[ -f "$FAKE_API/$(printf %s "$p" | tr / _)" ] || exit 22
cat "$FAKE_API/$(printf %s "$p" | tr / _)"
"""
FAKE_TAILSCALE = """#!/bin/sh
[ -n "$FAKE_TS" ] || exit 1
printf '{"BackendState": "%s"}\\n' "$FAKE_TS"
"""


@pytest.fixture
def status(tmp_path):
    bin_ = tmp_path / "bin"
    bin_.mkdir()
    for name, text in [("curl", FAKE_CURL), ("tailscale", FAKE_TAILSCALE)]:
        (bin_ / name).write_text(text)
        (bin_ / name).chmod(0o755)
    st = tmp_path / "syncthing"
    st.mkdir()
    (st / "config.xml").write_text("<configuration><gui><apikey>k</apikey></gui></configuration>\n")
    env_file = tmp_path / "tvhome.env"
    env_file.write_text(f"TVHOME_SYNCTHING_ID={TVHOME}\n")
    api = tmp_path / "api"
    api.mkdir()

    def run(ts="Running", connected=True, local=None, remote=None):
        (api / "system_connections").write_text(json.dumps(
            {"connections": {TVHOME: {"connected": connected}}}))
        if local is not None:
            (api / "db_status").write_text(json.dumps(local))
        if remote is not None:
            (api / "db_completion").write_text(json.dumps(remote))
        env = {**os.environ, "PATH": f"{bin_}:{os.environ['PATH']}", "FAKE_API": str(api),
               "FAKE_TS": ts or "", "TVBOX_ENV": str(env_file), "TVBOX_ST": str(st)}
        return subprocess.run(["sh", str(ROOT / "box" / "tvbox-status")], env=env,
                              capture_output=True, text=True)
    return run


DONE_LOCAL = {"state": "idle", "globalFiles": 11, "needFiles": 0, "needDeletes": 0, "needBytes": 0}
DONE_REMOTE = {"completion": 100, "needItems": 0, "needDeletes": 0, "remoteState": "valid"}


def test_up_to_date_says_so_with_the_count(status):
    r = status(local=DONE_LOCAL, remote=DONE_REMOTE)
    assert r.returncode == 0
    assert r.stdout == "On TV's tailnet.\nUp to date with tvhome (11 files).\n"


def test_while_starting_says_to_wait(status):
    r = status(ts="Starting", connected=False)
    assert "has just started" in r.stdout and "minute" in r.stdout
    assert "tv join" not in r.stdout
    r = status(ts=None, connected=False)
    assert "has just started" in r.stdout


def test_needs_login_points_to_join(status):
    r = status(ts="NeedsLogin", connected=False)
    assert r.returncode == 1 and "tv join" in r.stdout


def test_getting_documents_counts_what_is_left(status):
    r = status(local={**DONE_LOCAL, "state": "syncing", "needFiles": 3, "needBytes": 2202010},
               remote=DONE_REMOTE)
    assert r.returncode == 0
    assert "Getting TV's documents from tvhome: 3 of 11 files to go (2.1 MB)." in r.stdout


def test_sending_changes_counts_what_is_left(status):
    r = status(local=DONE_LOCAL, remote={**DONE_REMOTE, "completion": 80, "needItems": 2})
    assert "Sending your changes to tvhome: 2 files to go." in r.stdout
    assert "Up to date" not in r.stdout


def test_connected_but_folder_not_shared_yet(status):
    r = status(local={**DONE_LOCAL, "globalFiles": 0}, remote={**DONE_REMOTE, "remoteState": "notSharing"})
    assert "Up to date" not in r.stdout
    assert "hasn't shared TV's folder" in r.stdout


def test_not_connected_on_the_tailnet_mentions_stage_3(status):
    r = status(connected=False)
    assert r.returncode == 1
    assert "Not connected to tvhome's Syncthing" in r.stdout and "stage 3" in r.stdout
