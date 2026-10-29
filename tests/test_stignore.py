"""box/stignore: what Syncthing carries. Only TV's data, and never a file an
agent would take as instructions, or that runs code when its folder is
opened: those travel only by git, where tv catch-up shows them first (the
final review, 2026-10-29)."""
from pathlib import Path

LINES = (Path(__file__).resolve().parent.parent / "box" / "stignore").read_text().splitlines()
AGENT_FILES = ["CLAUDE.md", "CLAUDE.local.md", "AGENTS.md", "AGENT.md", "GEMINI.md", ".claude",
               ".agents", ".codex", ".cursor", ".cursorrules", ".windsurfrules", ".mcp.json",
               ".envrc", ".vscode"]


def test_agent_files_are_ignored_everywhere_before_the_data_dirs_are_let_in():
    first_include = next(n for n, line in enumerate(LINES) if line.startswith("!"))
    for name in AGENT_FILES:
        # Unanchored (any directory) and (?i): a Mac's disk ignores case.
        assert f"(?i){name}" in LINES[:first_include], name


def test_only_tvs_data_dirs_are_let_in():
    assert [line for line in LINES if line.startswith("!")] == \
        ["!/doc", "!/www", "!/ledger", "!/entity", "!/site"]
    assert LINES[-1] == "*"
