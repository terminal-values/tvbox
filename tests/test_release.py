"""mac/scripts/release.sh can't run for real without Danny's signing
credentials; these check it parses and refuses early, saying what's missing
or that it isn't the tagged commit, before it touches anything."""
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


# Releases are made on Danny's Mac, where the signing keys stay; GitHub
# holds none of them. So the build must be exactly the tagged commit.

CREDS = {name: "x" for name in ["TEAM_ID", "NOTARY_KEY", "NOTARY_KEY_ID", "NOTARY_ISSUER",
                                "SPARKLE_PUBLIC_KEY", "SPARKLE_PRIVATE_KEY_FILE", "SPARKLE_BIN"]}


def git(d, *args):
    subprocess.run(["git", "-C", str(d), *args], check=True, capture_output=True)


def a_repo(tmp_path):
    """A repository holding only release.sh, and a curl that leaves a mark,
    so a test can tell whether the script got as far as the network."""
    d = tmp_path / "repo"
    (d / "mac" / "scripts").mkdir(parents=True)
    (d / "mac" / "scripts" / "release.sh").write_text(SCRIPT.read_text())
    git(d, "init", "-q")
    git(d, "-c", "user.name=t", "-c", "user.email=t@example.org", "add", ".")
    git(d, "-c", "user.name=t", "-c", "user.email=t@example.org", "commit", "-qm", "one")
    bin_ = tmp_path / "bin"
    bin_.mkdir()
    (bin_ / "curl").write_text(f"#!/bin/sh\ntouch {tmp_path}/reached-network\nexit 1\n")
    (bin_ / "curl").chmod(0o755)
    (bin_ / "sleep").write_text("#!/bin/sh\nexit 0\n")
    (bin_ / "sleep").chmod(0o755)
    return d


def release_in(d, version):
    return subprocess.run(["sh", "mac/scripts/release.sh", version], capture_output=True, text=True,
                          cwd=d, env={"PATH": f"{d.parent}/bin:/usr/bin:/bin", **CREDS})


def test_refuses_a_version_with_no_tag(tmp_path):
    d = a_repo(tmp_path)
    r = release_in(d, "1.0.0")
    assert r.returncode != 0 and "v1.0.0" in r.stderr
    assert not (tmp_path / "reached-network").exists()


def test_refuses_when_the_tag_is_another_commit(tmp_path):
    d = a_repo(tmp_path)
    git(d, "tag", "v1.0.0")
    (d / "more").write_text("more")
    git(d, "-c", "user.name=t", "-c", "user.email=t@example.org", "add", "more")
    git(d, "-c", "user.name=t", "-c", "user.email=t@example.org", "commit", "-qm", "two")
    r = release_in(d, "1.0.0")
    assert r.returncode != 0 and "v1.0.0" in r.stderr
    assert not (tmp_path / "reached-network").exists()


def test_refuses_uncommitted_changes(tmp_path):
    # xcodegen takes every file in the source folders, committed or not.
    d = a_repo(tmp_path)
    git(d, "tag", "v1.0.0")
    (d / "stray.swift").write_text("")
    r = release_in(d, "1.0.0")
    assert r.returncode != 0 and "uncommitted" in r.stderr
    assert not (tmp_path / "reached-network").exists()


def test_goes_on_from_the_tagged_commit(tmp_path):
    d = a_repo(tmp_path)
    git(d, "tag", "-a", "-m", "v1.0.0", "v1.0.0")
    release_in(d, "1.0.0")
    assert (tmp_path / "reached-network").exists()


def test_no_workflow_holds_signing_secrets():
    # Only GitHub's own token, made for each run, to push the box image.
    import re
    for wf in (ROOT / ".github" / "workflows").glob("*.yml"):
        assert set(re.findall(r"secrets\.(\w+)", wf.read_text())) <= {"GITHUB_TOKEN"}, wf.name


def test_sparkles_tools_are_checked_and_match_the_app():
    make = (ROOT / "Makefile").read_text()
    project = (ROOT / "mac" / "project.yml").read_text()
    assert "1a856d2a9edb8e628de88121d7be04cf0e2167f8641650b78fca00b14244cf27" in make
    assert "shasum -a 256 -c" in make
    assert "SPARKLE_VERSION = 2.10.1" in make and 'exactVersion: "2.10.1"' in project
