"""box/tvbox-doctor: the box's half of tv doctor, run on the host against
fakes for tailscale, ssh, Syncthing's API and the pages (curl), and
age-keygen."""
import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TVHOME = "GGGGGGG-GGGGGGG-GGGGGGG-GGGGGGG-GGGGGGG-GGGGGGG-GGGGGGG-GGGGGGG"
SECRET = "AGE-SECRET-KEY-1QQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQQ"
PUBLIC = "age1sampleq7pqkjj6m9n4s5a4lxkq9r6x8xsg4n5q8t3vhvvqyvwqs2uqqa"

BOX_IDS = ["tailnet", "route", "tvhome-ssh", "tvhome-pages", "tvhome-sync", "sync-errors",
           "folder", "stignore", "age-key", "recipient", "disk-box"]


def fake(bin_, name, script):
    (bin_ / name).write_text("#!/bin/sh\n" + script + "\n")
    (bin_ / name).chmod(0o755)


@pytest.fixture
def doctor(tmp_path):
    bin_ = tmp_path / "bin"
    bin_.mkdir()
    fake(bin_, "tailscale", '''[ "$1 $2" = "status --json" ] || exit 1
printf '{"BackendState": "Running", "Self": {"Online": true}, "Peer": {"n1": {"HostName": "tvhome", "CurAddr": "%s", "Relay": "sfo", "Online": true}}}\\n' "${FAKE_CURADDR-1.2.3.4:41641}"''')
    fake(bin_, "ssh", 'exit "${FAKE_SSH:-0}"')
    fake(bin_, "age-keygen", '[ "$1" = -y ] && grep -q AGE-SECRET-KEY "$2" && echo ' + PUBLIC)
    # tvbox-status --json, answered whole: the doctor reads the sync state from it.
    fake(bin_, "tvbox-status", '''printf '{"tailnet": "on", "sync": {"connected": %s, "shared": %s, "waiting_for_list": false, "files": 11, "need_files": 0, "need_bytes": 0, "sending": 0}}\\n' "${FAKE_CONNECTED:-true}" "${FAKE_SHARED:-true}"''')
    fake(bin_, "curl", '''for a; do url=$a; done
case $url in
  *8484*) printf "${FAKE_PAGES:-200}" ;;
  *folder/errors*) printf '{"errors": %s}' "${FAKE_ERRORS:-null}" ;;
  *) exit 22 ;;
esac''')
    home, inside, secrets = tmp_path / "home", tmp_path / "folder", tmp_path / "secrets"
    (home / ".passage").mkdir(parents=True)
    (home / ".passage/identities").write_text(SECRET + "\n")
    inside.mkdir()
    stignore = tmp_path / "stignore"
    stignore.write_text("!/doc\n*\n")
    (inside / ".stignore").write_text("!/doc\n*\n")
    secrets.mkdir()
    (secrets / ".age-recipients").write_text(f"# sam\n{PUBLIC}\n")
    st = tmp_path / "syncthing"
    st.mkdir()
    (st / "config.xml").write_text("<apikey>k</apikey>\n")
    env_file = tmp_path / "tvhome.env"
    env_file.write_text(f"TVHOME_SYNCTHING_ID={TVHOME}\nTVHOME_HOST=tvhome.example.ts.net\n")

    def run(**fakes):
        env = {**os.environ, "PATH": f"{bin_}:{os.environ['PATH']}", "HOME": str(home),
               "TVBOX_ENV": str(env_file), "TVBOX_ST": str(st), "TVBOX_INSIDE": str(inside),
               "PASSAGE_DIR": str(secrets), "TVBOX_STIGNORE": str(stignore), "TVBOX_STATE": str(tmp_path),
               **{f"FAKE_{k.upper()}": v for k, v in fakes.items()}}
        r = subprocess.run(["sh", str(ROOT / "box" / "tvbox-doctor"), "--json"], env=env,
                           capture_output=True, text=True)
        return r, {x["id"]: x for x in json.loads(r.stdout)["results"]} if r.stdout else {}
    run.secrets, run.inside = secrets, inside
    return run


def test_all_ok_in_order(doctor):
    r, res = doctor()
    assert r.returncode == 0, r.stderr
    assert list(res) == BOX_IDS
    assert {k: v["status"] for k, v in res.items()} == {k: "ok" for k in BOX_IDS}


def test_relayed_route_is_a_warning(doctor):
    r, res = doctor(curaddr="")
    assert res["route"]["status"] == "warning" and "relay" in res["route"]["message"]


def test_key_not_a_recipient_is_a_problem(doctor):
    (doctor.secrets / ".age-recipients").write_text("# other\nage1someoneelse\n")
    r, res = doctor()
    assert res["recipient"]["status"] == "problem"


def test_no_secrets_yet_suggests_catch_up(doctor):
    (doctor.secrets / ".age-recipients").unlink()
    r, res = doctor()
    assert res["recipient"]["status"] == "warning" and res["recipient"]["fix"] == "catch-up"


def test_unreachable_tvhome_and_unshared_folder(doctor):
    r, res = doctor(ssh="255", pages="000", shared="false")
    assert res["tvhome-ssh"]["status"] == "problem"
    assert res["tvhome-pages"]["status"] == "problem"
    assert res["tvhome-sync"]["status"] == "problem" and "Danny" in res["tvhome-sync"]["message"]


def test_sync_errors_are_counted(doctor):
    r, res = doctor(errors='[{"path": "doc/a.md", "error": "permission denied"}]')
    assert res["sync-errors"]["status"] == "warning" and "doc/a.md" in res["sync-errors"]["message"]


def test_a_changed_stignore_is_a_warning(doctor):
    (doctor.inside / ".stignore").write_text("*\n")
    r, res = doctor()
    assert res["stignore"]["status"] == "warning"


def test_never_prints_the_age_key(doctor):
    r, res = doctor()
    assert "AGE-SECRET-KEY" not in r.stdout + r.stderr
