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
printf '{"BackendState": "%s", "Self": {"Online": %s}}\\n' "$FAKE_TS" "${FAKE_ONLINE:-true}"
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

    def run(ts="Running", connected=True, local=None, remote=None, online="true", args=()):
        (api / "system_connections").write_text(json.dumps(
            {"connections": {TVHOME: {"connected": connected}}}))
        if local is not None:
            (api / "db_status").write_text(json.dumps(local))
        if remote is not None:
            (api / "db_completion").write_text(json.dumps(remote))
        env = {**os.environ, "PATH": f"{bin_}:{os.environ['PATH']}", "FAKE_API": str(api),
               "FAKE_TS": ts or "", "FAKE_ONLINE": online,
               "TVBOX_ENV": str(env_file), "TVBOX_ST": str(st)}
        return subprocess.run(["sh", str(ROOT / "box" / "tvbox-status"), *args], env=env,
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


def test_before_tvhome_has_sent_its_list_it_doesnt_claim_up_to_date(status):
    # Found in the Linux run: a new machine said "Up to date with tvhome
    # (0 files)" before it had heard what tvhome has.
    r = status(local={**DONE_LOCAL, "globalFiles": 0}, remote=DONE_REMOTE)
    assert "Up to date" not in r.stdout
    assert "Waiting for tvhome's list of TV's documents" in r.stdout


def test_a_box_off_the_tailnet_doesnt_trust_a_stale_connection(status):
    # Found removing tvlinux: its box still said "On TV's tailnet. Up to date"
    # minutes later. Tailscale knew it was offline; Syncthing hadn't noticed.
    r = status(online="false", local=DONE_LOCAL, remote=DONE_REMOTE)
    assert r.returncode == 1
    assert "On TV's tailnet" not in r.stdout and "Up to date" not in r.stdout
    assert "removed" in r.stdout and "offline" in r.stdout


# --- --json, for the Mac app ------------------------------------------------

def sync(**kw):
    base = {"connected": True, "shared": True, "waiting_for_list": False, "files": 11,
            "need_files": 0, "need_bytes": 0, "sending": 0}
    return {**base, **kw}


def test_json_up_to_date(status):
    r = status(local=DONE_LOCAL, remote=DONE_REMOTE, args=["--json"])
    assert r.returncode == 0
    assert json.loads(r.stdout) == {"tailnet": "on", "sync": sync()}


def test_json_getting_documents(status):
    r = status(local={**DONE_LOCAL, "needFiles": 3, "needBytes": 2202010},
               remote={**DONE_REMOTE, "needItems": 2}, args=["--json"])
    assert json.loads(r.stdout) == {"tailnet": "on",
                                    "sync": sync(need_files=3, need_bytes=2202010, sending=2)}


def test_json_offline(status):
    r = status(online="false", local=DONE_LOCAL, remote=DONE_REMOTE, args=["--json"])
    assert r.returncode == 0
    out = json.loads(r.stdout)
    assert out["tailnet"] == "offline" and out["sync"]["connected"] is False


def test_json_waiting_for_list(status):
    r = status(local={**DONE_LOCAL, "globalFiles": 0}, remote=DONE_REMOTE, args=["--json"])
    assert json.loads(r.stdout)["sync"] == sync(files=0, waiting_for_list=True)


def test_json_not_connected_and_not_shared(status):
    r = status(ts="Starting", connected=False, args=["--json"])
    out = json.loads(r.stdout)
    assert out["tailnet"] == "connecting" and out["sync"]["connected"] is False
    r = status(local=DONE_LOCAL, remote={**DONE_REMOTE, "remoteState": "notSharing"}, args=["--json"])
    assert json.loads(r.stdout)["sync"]["shared"] is False
    r = status(ts="NeedsLogin", connected=False, args=["--json"])
    assert json.loads(r.stdout)["tailnet"] == "not-joined"
