"""box/tvbox-phone, run on the host against a fake curl (the pairing service)
and a fake qrencode."""
import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent

# Prints $FAKE_BODY, then a newline and $FAKE_CODE, as curl -w '\n%{http_code}'
# would; records its arguments in $FAKE_LOG.
FAKE_CURL = """#!/bin/sh
printf '%s\\n' "$*" >> "$FAKE_LOG/curl"
[ -n "${FAKE_EXIT:-}" ] && exit "$FAKE_EXIT"
printf '%s\\n%s' "$FAKE_BODY" "$FAKE_CODE"
"""
FAKE_QRENCODE = """#!/bin/sh
for a; do url=$a; done
printf '%s\\n' "$url" > "$FAKE_LOG/qr"
echo "[QR CODE]"
"""
OK = json.dumps({"key": "tskey-auth-FAKE", "expires": 600})
INSTRUCTIONS = """Scan this with your phone's camera and open the link. It works for ten
minutes, for one phone.
Pair in the browser your links open in. On an iPhone, use Safari or
Firefox; Brave doesn't keep the pairing working yet.
Don't add the page to your home screen: it wouldn't see the pairing.
"""


@pytest.fixture
def phone(tmp_path):
    bin_ = tmp_path / "bin"
    bin_.mkdir()
    for name, text in [("curl", FAKE_CURL), ("qrencode", FAKE_QRENCODE)]:
        (bin_ / name).write_text(text)
        (bin_ / name).chmod(0o755)
    (tmp_path / "tvhome.env").write_text("TVHOME_HOST=tvhome.example-tailnet.ts.net\n")
    log = tmp_path / "log"
    log.mkdir()

    def run(code="200", body=OK, args=(), exit_=None):
        env = {**os.environ, "PATH": f"{bin_}:{os.environ['PATH']}", "FAKE_LOG": str(log),
               "FAKE_BODY": body, "FAKE_CODE": code, "FAKE_EXIT": exit_ or "",
               "TVBOX_ENV": str(tmp_path / "tvhome.env")}
        r = subprocess.run(["sh", str(ROOT / "box" / "tvbox-phone"), *args], env=env,
                           capture_output=True, text=True)
        r.log = log
        return r
    return run


def test_qr_shown(phone):
    r = phone()
    assert r.returncode == 0
    assert (r.log / "qr").read_text().strip() == "https://box.terminalvalues.org/#join=tskey-auth-FAKE"
    assert r.stdout == "[QR CODE]\n" + INSTRUCTIONS
    assert "tskey-" not in r.stdout + r.stderr
    curl = (r.log / "curl").read_text()
    assert "--socks5-hostname 127.0.0.1:1055" in curl
    assert "http://tvhome.example-tailnet.ts.net:8081/phone-key" in curl


def test_json(phone):
    r = phone(args=["--json"])
    assert r.returncode == 0
    assert json.loads(r.stdout) == {"url": "https://box.terminalvalues.org/#join=tskey-auth-FAKE",
                                    "expires": 600}
    assert not (r.log / "qr").exists()


def test_base(phone):
    r = phone(args=["--base", "https://phonetest.example"])
    assert (r.log / "qr").read_text().strip() == "https://phonetest.example/#join=tskey-auth-FAKE"


@pytest.mark.parametrize("code,body,want", [
    ("403", {"error": "not a member"}, "TVhome won't pair a phone for this box: not a member"),
    ("429", {"error": "slow down", "retry": 1500},
     "You've paired a lot of phones this hour; try again in 25 minutes"),
    ("429", {"error": "slow down", "retry": 61},
     "You've paired a lot of phones this hour; try again in 2 minutes"),
    ("502", {"error": "upstream"}, "TVhome couldn't make a key just now; try again in a minute"),
])
def test_service_error(phone, code, body, want):
    r = phone(code=code, body=json.dumps(body))
    assert r.returncode == 1
    assert r.stdout == ""
    assert r.stderr.strip() == want
    assert not (r.log / "qr").exists()


def test_unreachable(phone):
    r = phone(exit_="7")
    assert r.returncode == 1
    assert r.stderr.strip() == ("Couldn't reach TVhome's pairing service. "
                                "Is the box on TV's tailnet? (tv status)")
