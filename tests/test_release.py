"""mac/scripts/release.sh can't run for real without Danny's signing
credentials; these check it parses and refuses early, saying what's missing,
before it touches anything."""
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "mac" / "scripts" / "release.sh"


def run(*args, env=None):
    return subprocess.run(["sh", str(SCRIPT), *args], capture_output=True, text=True,
                          env=env or {"PATH": "/usr/bin:/bin"}, cwd=ROOT)


def test_it_parses():
    assert subprocess.run(["sh", "-n", str(SCRIPT)]).returncode == 0


def test_needs_a_version():
    r = run()
    assert r.returncode != 0 and "VERSION" in r.stderr


def test_says_every_missing_credential_before_doing_anything():
    r = run("0.1.0")
    assert r.returncode != 0
    for name in ["TEAM_ID", "NOTARY_KEY", "NOTARY_KEY_ID", "NOTARY_ISSUER", "SPARKLE_PUBLIC_KEY",
                 "SPARKLE_PRIVATE_KEY_FILE", "SPARKLE_BIN"]:
        assert name in r.stderr, name
    assert not (ROOT / "mac" / "TerminalValues" / "BoxImage.plist").exists()


def test_the_dmg_is_signed_before_it_is_notarized():
    # Found in the first release: the .dmg carried a stapled notarization but
    # no signature of its own, which Gatekeeper's strict check rejects.
    text = SCRIPT.read_text()
    sign = text.index('codesign --sign "Developer ID Application" --timestamp "$dmg"')
    assert sign < text.index('notarize "$dmg"')
