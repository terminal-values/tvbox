"""box/tvbox-catch-up (tv catch-up; moved here from TV's own bin/tv-catch-up
on 2026-10-30, so the Mac app's contract is versioned with tv). Syncthing carries TV's documents (doc/ www/ ledger/
entity/ site/), which git doesn't track at all; code and agent instructions
come only through git, and a member sees incoming code changes before
they're applied. The secrets store is wherever PASSAGE_DIR says (the box's
/state/secrets)."""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
TOOL = ROOT / "box" / "tvbox-catch-up"


def git(cwd, *args):
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout


@pytest.fixture
def world(tmp_path):
    """A tvhome remote, Alice's checkout (which pushes), and Bob's (who catches up)."""
    remote = tmp_path / "tvhome.git"
    git(tmp_path, "init", "-q", "--bare", "-b", "main", str(remote))
    alice = tmp_path / "alice"
    git(tmp_path, "clone", "-q", "-o", "tvhome", str(remote), str(alice))
    for name, text in [("bin/tool", "v1\n"), ("CLAUDE.md", "rules v1\n")]:
        (alice / name).parent.mkdir(parents=True, exist_ok=True)
        (alice / name).write_text(text)
    git(alice, "add", "-A")
    git(alice, "-c", "user.name=A", "-c", "user.email=a@x", "commit", "-q", "-m", "start")
    git(alice, "push", "-q", "tvhome", "main")
    bob = tmp_path / "bob"
    git(tmp_path, "clone", "-q", "-o", "tvhome", str(remote), str(bob))
    (bob / "doc").mkdir()
    (bob / "doc/notes.md").write_text("notes, by Syncthing\n")
    secrets = tmp_path / "bob-secrets"
    git(tmp_path, "clone", "-q", "-o", "tvhome", str(remote), str(secrets))
    os.environ["PASSAGE_DIR"] = str(secrets)
    return alice, bob


def alice_changes(alice, code="v2\n"):
    (alice / "bin/tool").write_text(code)
    git(alice, "-c", "user.name=A", "-c", "user.email=a@x", "commit", "-q", "-am", "alice's change")
    git(alice, "push", "-q", "tvhome", "main")


def catch_up(bob, answer="", yes=False, args=()):
    # The box has a git identity, which a rebase needs. TVBOX_INSIDE stands
    # in for the box's /home/tv/terminalvalues; tvhome.env isn't needed once
    # the checkout exists.
    env = dict(os.environ, GIT_COMMITTER_NAME="B", GIT_COMMITTER_EMAIL="b@x", TVBOX_INSIDE=str(bob),
               TVBOX_ENV="/dev/null")
    argv = ["bash", str(TOOL), *(["--yes"] if yes else []), *args]
    return subprocess.run(argv, cwd=bob, input=answer, capture_output=True, text=True, env=env)


def test_code_arrives_by_git_after_a_yes(world):
    alice, bob = world
    alice_changes(alice)
    r = catch_up(bob, answer="y\n")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "bin/tool" in r.stdout  # shown before it's applied
    assert (bob / "bin/tool").read_text() == "v2\n"
    assert git(bob, "status", "--short", "--untracked-files=no") == ""


def test_saying_no_changes_nothing(world):
    alice, bob = world
    alice_changes(alice)
    head = git(bob, "rev-parse", "HEAD")
    r = catch_up(bob, answer="n\n")
    assert r.returncode != 0
    assert (bob / "bin/tool").read_text() == "v1\n"
    assert git(bob, "rev-parse", "HEAD") == head


def test_documents_are_none_of_its_business(world):
    alice, bob = world
    alice_changes(alice)
    r = catch_up(bob, yes=True)
    assert r.returncode == 0, r.stdout + r.stderr
    assert (bob / "doc/notes.md").read_text() == "notes, by Syncthing\n"
    assert "doc/" not in r.stdout


def bob_commits(bob, name="bin/new", text="mine\n"):
    (bob / name).write_text(text)
    git(bob, "add", name)
    git(bob, "-c", "user.name=B", "-c", "user.email=b@x", "commit", "-q", "-m", "bob's")


def test_own_commits_go_on_top_of_what_came_in(world):
    # The final review: with commits on both sides, tv push was refused and
    # catch-up refused too, leaving only a git pull that applied code unseen.
    alice, bob = world
    alice_changes(alice)
    bob_commits(bob)
    r = catch_up(bob, answer="y\n")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "alice's change" in r.stdout  # shown before it's applied
    assert (bob / "bin/tool").read_text() == "v2\n" and (bob / "bin/new").read_text() == "mine\n"
    assert git(bob, "log", "--format=%s", "tvhome/main..HEAD").strip() == "bob's"
    assert "tv push" in r.stdout


def test_a_conflict_leaves_things_as_they_were(world):
    alice, bob = world
    alice_changes(alice)
    bob_commits(bob, "bin/tool", "bob's v2\n")
    head = git(bob, "rev-parse", "HEAD")
    r = catch_up(bob, yes=True)
    assert r.returncode != 0
    assert "bin/tool" in r.stdout + r.stderr
    assert git(bob, "rev-parse", "HEAD") == head
    assert not (bob / ".git" / "rebase-merge").exists() and not (bob / ".git" / "rebase-apply").exists()
    assert (bob / "bin/tool").read_text() == "bob's v2\n"


def test_refuses_with_uncommitted_code_edits(world):
    alice, bob = world
    alice_changes(alice)
    (bob / "bin/tool").write_text("bob's local edit\n")
    r = catch_up(bob, yes=True)
    assert r.returncode != 0
    assert (bob / "bin/tool").read_text() == "bob's local edit\n"


# --- the secrets store ------------------------------------------------------

@pytest.fixture
def secrets_world(world, tmp_path):
    """Secrets of their own: a tvhome remote, Alice's store and Bob's."""
    alice, bob = world
    remote = tmp_path / "secrets.git"
    git(tmp_path, "init", "-q", "--bare", "-b", "main", str(remote))
    a = tmp_path / "alice-secrets"
    git(tmp_path, "clone", "-q", "-o", "tvhome", str(remote), str(a))
    (a / ".age-recipients").write_text("# alice\nage1alice\n# bob\nage1bob\n")
    (a / "welcome").mkdir()
    (a / "welcome/bob.age").write_text("x")
    git(a, "add", "-A")
    git(a, "-c", "user.name=A", "-c", "user.email=a@x", "commit", "-q", "-m", "start")
    git(a, "push", "-q", "tvhome", "main")
    b = tmp_path / "bob-store"
    git(tmp_path, "clone", "-q", "-o", "tvhome", str(remote), str(b))
    os.environ["PASSAGE_DIR"] = str(b)
    return a, b, bob


def secrets_commit(store, name, text, who="A"):
    (store / name).parent.mkdir(parents=True, exist_ok=True)
    (store / name).write_text(text)
    git(store, "add", "-A")
    git(store, "-c", f"user.name={who}", "-c", "user.email=x@x", "commit", "-q", "-m", f"{name}")


def test_a_new_recipient_is_shown_and_asked_about(secrets_world):
    a, b, bob = secrets_world
    secrets_commit(a, ".age-recipients", "# alice\nage1alice\n# bob\nage1bob\n# eve\nage1eve\n")
    git(a, "push", "-q", "tvhome", "main")
    r = catch_up(bob, answer="n\n")
    assert "age1eve" in r.stdout and "eve" in r.stdout
    assert r.returncode != 0
    assert "age1eve" not in (b / ".age-recipients").read_text()
    r = catch_up(bob, answer="y\n")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "age1eve" in (b / ".age-recipients").read_text()


def test_recipients_in_a_subdirectory_count_too(secrets_world):
    # passage encrypts entries below a directory to its own .age-recipients.
    a, b, bob = secrets_world
    secrets_commit(a, "bank/.age-recipients", "age1outsider\n")
    git(a, "push", "-q", "tvhome", "main")
    r = catch_up(bob, answer="n\n")
    assert "bank/.age-recipients" in r.stdout and "age1outsider" in r.stdout
    assert not (b / "bank").exists()


def test_secrets_with_commits_on_both_sides_are_rebased(secrets_world):
    a, b, bob = secrets_world
    secrets_commit(a, "bank/a.age", "a")
    git(a, "push", "-q", "tvhome", "main")
    secrets_commit(b, "bank/b.age", "b", who="B")
    r = catch_up(bob, yes=True)
    assert r.returncode == 0, r.stdout + r.stderr
    assert (b / "bank/a.age").exists() and (b / "bank/b.age").exists()
    assert git(b, "log", "--format=%s", "tvhome/main..HEAD").strip() == "bank/b.age"


# --- tv changes, and a pinned --yes, for the Mac app --------------------------

import json  # noqa: E402


def head(repo, ref="HEAD"):
    return git(repo, "rev-parse", ref).strip()


def test_changes_json_lists_incoming_mine_and_readers(secrets_world):
    a, b, bob = secrets_world
    alice = bob.parent / "alice"
    alice_changes(alice)
    bob_commits(bob)
    secrets_commit(a, ".age-recipients", "# alice\nage1alice\n# bob\nage1bob\n# eve\nage1eve\n")
    git(a, "push", "-q", "tvhome", "main")
    r = catch_up(bob, args=["--changes"])
    assert r.returncode == 0, r.stdout + r.stderr
    out = json.loads(r.stdout)
    remote = bob.parent / "tvhome.git"
    assert out["code"]["to"] == head(remote, "main")
    assert [c["subject"] for c in out["code"]["incoming"]] == ["alice's change"]
    assert out["code"]["incoming"][0]["author"] == "A"
    assert out["code"]["files"] == ["bin/tool"]
    assert [c["subject"] for c in out["code"]["mine"]] == ["bob's"]
    assert out["code"]["diff"] is None
    assert out["secrets"]["to"] == head(a)
    assert "age1eve" in out["secrets"]["readers_diff"]
    assert out["secrets"]["mine"] == 0
    assert [c["subject"] for c in out["recent"]][0] == "alice's change"
    assert head(bob) != out["code"]["to"]  # read-only
    r = catch_up(bob, args=["--changes", "--diff"])
    assert "+v2" in json.loads(r.stdout)["code"]["diff"]


def test_yes_applies_exactly_what_was_shown(secrets_world):
    a, b, bob = secrets_world
    alice_changes(bob.parent / "alice")
    shown = json.loads(catch_up(bob, args=["--changes"]).stdout)
    r = catch_up(bob, yes=True, args=["--to", shown["code"]["to"], "--secrets-to", shown["secrets"]["to"]])
    assert r.returncode == 0, r.stdout + r.stderr
    assert head(bob) == shown["code"]["to"] and (bob / "bin/tool").read_text() == "v2\n"


def test_yes_refuses_if_tvhome_moved_on(secrets_world):
    a, b, bob = secrets_world
    alice = bob.parent / "alice"
    alice_changes(alice)
    shown = json.loads(catch_up(bob, args=["--changes"]).stdout)
    alice_changes(alice, code="v3, not reviewed\n")
    before = head(bob)
    r = catch_up(bob, yes=True, args=["--to", shown["code"]["to"], "--secrets-to", shown["secrets"]["to"]])
    assert r.returncode == 4
    assert "review again" in r.stdout + r.stderr
    assert head(bob) == before and (bob / "bin/tool").read_text() == "v1\n"


def test_yes_refuses_if_secrets_moved_on(secrets_world):
    a, b, bob = secrets_world
    shown = json.loads(catch_up(bob, args=["--changes"]).stdout)
    secrets_commit(a, ".age-recipients", "# alice\nage1alice\n# bob\nage1bob\n# mallory\nage1mallory\n")
    git(a, "push", "-q", "tvhome", "main")
    r = catch_up(bob, yes=True, args=["--to", shown["code"]["to"], "--secrets-to", shown["secrets"]["to"]])
    assert r.returncode == 4
    assert "age1mallory" not in (b / ".age-recipients").read_text()
