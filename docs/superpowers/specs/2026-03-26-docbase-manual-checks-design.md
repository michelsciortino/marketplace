# DocBase Manual Checks Design

**Date:** 2026-03-26
**Topic:** Replace auto-trigger hook with two manual check commands

## Context

The existing `docbase-stop.sh` hook fires whenever Claude stops modifying files. This is premature — it runs mid-session before the user has finished writing docs, producing noise and spurious findings. The goal is to make consistency checks explicit, user-initiated, and CI/CD-ready.

## What Changes

### Removed

- `hooks/docbase-stop.sh` — the automatic doc integrity trigger
- `hooks/docbase-track-change.sh` — only existed to feed the stop hook
- `hooks/docbase-post-commit.sh` — the automatic code→doc trigger on commit
- `commands/docbase/check-consistency.md` — replaced by the two new commands below

All automatic triggers are removed. Claude commits incrementally while working, so any hook firing mid-session operates on incomplete code and produces spurious findings.

### Added

Two new manual commands that replace the removed combined sweep.

---

## `/docbase:check-docs` — Doc cross-reference consistency

**Purpose:** Check that all documentation files are internally consistent with each other.

**Steps:**
1. Read `.docbase.json`, resolve `doc_root`, `issues_dir`.
2. Spawn a sub-agent to sweep all `.md` files under `doc_root` that have DocBase frontmatter.
3. The sub-agent checks:
   - **Broken links:** every path in `related:` entries resolves to an existing file
   - **Asymmetric links:** if A lists B in `related:`, B must list A
   - **Semantic conflicts:** related files agree on field names, types, API shapes, behaviors — no direct contradictions
4. Write new issue files to `issues_dir`; auto-close issues whose conflict no longer exists.
5. Present human-readable findings to the user.
6. Append a machine-readable JSON block:

```json
{
  "check": "docs",
  "status": "pass" | "fail",
  "total": <N>,
  "issues": [
    { "type": "broken-link" | "asymmetric-link" | "semantic-conflict", "file": "<path>", "related_file": "<path>", "issue": "<description>" }
  ]
}
```

---

## `/docbase:check-code` — Code↔doc conformance

**Purpose:** Check that source code correctly implements what the documentation specifies.

**Steps:**
1. Read `.docbase.json`, resolve `doc_root`, `source_roots`, `issues_dir`.
2. Spawn a sub-agent to:
   - Find all docs with `implementation:` entries; for each linked file check existence (doc-drift) and conformance (API signatures, field names, behaviors)
   - Find all source files under `source_roots` not referenced by any doc (undocumented)
   - Write new issue files to `issues_dir`; auto-close issues whose conflict no longer exists
3. Present human-readable findings to the user.
4. Append a machine-readable JSON block:

```json
{
  "check": "code",
  "status": "pass" | "fail",
  "total": <N>,
  "issues": [
    { "type": "conformance" | "doc-drift" | "undocumented", "doc": "<path>", "code": "<path>", "issue": "<description>" }
  ]
}
```

---

## Updated: `/docbase:init`

- Remove the step instructing users to copy hook files and register them in `~/.claude/settings.json` (no hooks to install).
- Remove the step that installs `docbase-post-commit.sh` into `.git/hooks/post-commit`.
- Remove the prerequisite check that warns if the directory is not a git repo (git is no longer needed for any DocBase trigger).
- Update the final suggestion: recommend running `/docbase:check-docs` after writing docs, and `/docbase:check-code` after implementing them.

---

## Updated: `README.md`

- Rewrite "How It Works" table: remove the auto-trigger row, document the two manual commands.
- Remove hook installation from the setup instructions.
- Update the command table to list `check-docs` and `check-code` instead of `check-consistency`.

---

## CI/CD Vision (future)

The JSON output blocks are designed to support a future CI/CD pipeline:

1. On PR push: run `/docbase:check-docs` → parse JSON → if `status: fail`, post issues as PR comment, block merge
2. If docs pass: run `/docbase:check-code` → parse JSON → same
3. If code passes: run unit tests as final gate

The commands' output format is stable by design — the CI/CD layer will consume the JSON block, the human-readable section is for local use only.
