# DocBase Validation Scripts Design

**Date:** 2026-03-26
**Topic:** Add bash validation scripts to handle mechanical checks, leaving AI sub-agents for semantic analysis only

## Context

The current `check-docs.md` and `check-code.md` commands delegate all work to AI sub-agents. Mechanical checks (broken links, doc-drift, undocumented files) are deterministic and don't require AI — they can be done faster, more reliably, and with no token cost via bash scripts. This design adds two scripts that handle the mechanical layer, feeding clean structured input to sub-agents that focus exclusively on semantic analysis.

## File Structure

```
external_plugins/docbase/
├── scripts/
│   ├── check-links.sh    # mechanical checks for /docbase:check-docs
│   └── check-drift.sh    # mechanical checks for /docbase:check-code
├── commands/docbase/
│   ├── check-docs.md     # updated: script phase → sub-agent phase
│   ├── check-code.md     # updated: script phase → sub-agent phase
│   └── ...
└── README.md
```

Scripts are installed with the plugin at `~/.claude/plugins/cache/docbase/scripts/`. Commands reference them by that path — no `init` step needed.

---

## Link Model: Directed Graph

Documentation links are **directed edges**, not symmetric pairs. `A → B` means "A depends on or references something in B." B has no obligation to reference A back.

When B changes, the system traverses the graph backwards to find all documents that reference B and checks those edges for consistency. The direction of the edge determines the dependency, not the other way around.

**Cycles** (A → B and B → A) are valid and expected. The script detects them and flags both edges. The sub-agent checks consistency in both directions and reports any conflict. The human decides which document is authoritative — the system does not auto-resolve.

---

## Git-Aware Scoping

Both commands use git to identify which files changed since the last push, scoping the semantic phase to only the edges affected by those changes. The mechanical phase (script) always runs a full sweep — broken links and drift need full coverage regardless of what changed. The semantic phase (sub-agent) is expensive and should focus only on what actually changed.

**How the command resolves changed files:**
```bash
git diff --name-only origin/$(git rev-parse --abbrev-ref HEAD)..HEAD
```
If no remote exists or the branch has no upstream, fall back to:
```bash
git diff --name-only HEAD~1..HEAD
```

The resulting list of changed files is passed to the script and to the sub-agent. The script marks each valid edge as `"affected": true` if at least one endpoint (`from` or `to`) appears in the changed file list. The sub-agent only checks affected edges.

If no files changed (e.g., on a fresh clone or clean working tree), all edges are treated as affected — full semantic sweep.

---

## `scripts/check-links.sh`

Backs `/docbase:check-docs`. Handles all mechanical link checks.

**Input (positional args):** `PROJECT_ROOT`, `DOC_ROOT`, `ISSUES_DIR`, `CHANGED_FILES` (newline-separated list, optional — omit or pass empty string for full sweep)

**Steps:**

1. Find all `.md` files recursively under `DOC_ROOT` with DocBase frontmatter (YAML block containing at least one of: `related`, `implementation`, `layer`, `status`).

2. For each file, collect all references:
   - Extract `related:` frontmatter entries (path portion of each markdown link `[text](path)`)
   - Extract all markdown links in the document body pointing to `.md` files within `DOC_ROOT`
   - Union = frontmatter refs ∪ body refs

3. For each body link not present in `related:` frontmatter:
   - Write an `undeclared-reference` issue file to `ISSUES_DIR`

4. For each link in the union:
   - Resolve to absolute path
   - If the file does not exist: write a `broken-link` issue file

5. Build the directed graph from all valid edges (both source and target exist).

6. Detect cycles: if A → B and B → A, mark both edges with `"cycle": true`. A cycle is not inherently a problem — the script does NOT write any issue file for cycles. The `cycle` flag is informational only, passed to the sub-agent so it knows to check both directions and, if a semantic conflict is found, prompt the user to decide which document is authoritative.

7. Mark affected edges: for each edge, if either `from` or `to` appears in `CHANGED_FILES`, mark it `"affected": true`. If `CHANGED_FILES` is empty, all edges are `"affected": true`.

8. Auto-close resolved issues: for each existing issue file in `ISSUES_DIR` with type `undeclared-reference` or `broken-link`, re-check if the problem still exists. If resolved, delete the file.

9. Output JSON to stdout:
```json
{
  "undeclared_references": 2,
  "broken_links": 1,
  "valid_edges": [
    { "from": "docs/api/meals.md", "to": "docs/data/ingredients.md", "cycle": false, "affected": true },
    { "from": "docs/data/ingredients.md", "to": "docs/api/meals.md", "cycle": true, "affected": true }
  ]
}
```

---

## `scripts/check-drift.sh`

Backs `/docbase:check-code`. Handles all mechanical doc↔code checks.

**Input (positional args):** `PROJECT_ROOT`, `DOC_ROOT`, `ISSUES_DIR`, `SOURCE_ROOTS` (JSON string), `CHANGED_FILES` (newline-separated list, optional — omit or pass empty string for full sweep)

**Steps:**

1. Find all `.md` files under `DOC_ROOT` with `implementation:` frontmatter entries. Extract each implementation path.

2. For each implementation path:
   - Resolve to absolute path
   - If the file does not exist: write a `doc-drift` issue file

3. Find all source files under each directory in `SOURCE_ROOTS`.

4. For each source file: check if any doc's `implementation:` references it. If none do: write an `undocumented` issue file.

5. Mark affected pairs: for each valid pair, if either the doc or code file appears in `CHANGED_FILES`, mark it `"affected": true`. If `CHANGED_FILES` is empty, all pairs are `"affected": true`.

6. Auto-close resolved issues: for each existing issue file in `ISSUES_DIR` with type `doc-drift` or `undocumented`, re-check. If resolved, delete.

7. Output JSON to stdout:
```json
{
  "doc_drift": 1,
  "undocumented": 3,
  "valid_impl_pairs": [
    { "doc": "docs/services/meals.md", "code": "backend/src/services/meals.ts", "affected": true }
  ]
}
```

---

## Updated: `/docbase:check-docs`

Three-phase structure:

**Phase 0 — Git diff:**
1. Check prerequisites, resolve `PROJECT_ROOT`, `DOC_ROOT`, `ISSUES_DIR`.
2. Resolve changed files:
   ```bash
   git diff --name-only origin/$(git rev-parse --abbrev-ref HEAD)..HEAD
   ```
   Fall back to `git diff --name-only HEAD~1..HEAD` if no upstream. Store as `CHANGED_FILES`.

**Phase 1 — Script (mechanical):**
3. Run `~/.claude/plugins/cache/docbase/scripts/check-links.sh PROJECT_ROOT DOC_ROOT ISSUES_DIR "$CHANGED_FILES"` via Bash tool.
4. Parse JSON output.
5. Report mechanical findings to user: undeclared references found, broken links found.

**Phase 2 — Sub-agent (semantic only):**
6. Filter `valid_edges` to only those with `"affected": true`. If none remain, skip sub-agent and report clean.
7. Spawn sub-agent with the affected edge list, the full git diff for changed files, and the resolved content of all referenced files.

   The sub-agent prompt must instruct:
   - For each edge A→B: read both files and the git diff for any changed endpoint. Check whether A's content that references B is still semantically consistent with B's current content.
   - **Transitive reference reasoning:** if B has changed and now references C (B→C), and the content A was depending on appears to have moved from B to C, flag a `semantic-conflict` with type `stale-reference`: *"A references B for [topic], which appears to have moved to C (via B→C). Consider whether A should directly reference C, or whether the transitive chain A→B→C is sufficient."* The human decides — the system does not auto-update.
   - For cycle edges (`"cycle": true`): check both directions. If content diverges, write a `semantic-conflict` issue with a note that it is a cyclic reference, asking the user which document is authoritative. If consistent, write no issue.
   - Sub-agent writes `semantic-conflict` issue files only when content actually diverges.
   - Sub-agent auto-closes resolved `semantic-conflict` issues.
   - Sub-agent returns JSON: `{ "semantic_conflicts": N, "issues": [...] }`

**Phase 3 — Report:**
6. Merge script counts + sub-agent counts.
7. Present human-readable summary to user.
8. Output `docbase-result` JSON block:
```json
{
  "check": "docs",
  "status": "pass"|"fail",
  "total": N,
  "issues": [...]
}
```

---

## Updated: `/docbase:check-code`

Three-phase structure:

**Phase 0 — Git diff:**
1. Check prerequisites, resolve `PROJECT_ROOT`, `DOC_ROOT`, `ISSUES_DIR`, `SOURCE_ROOTS`.
2. Resolve changed files (same logic as check-docs). Store as `CHANGED_FILES`.

**Phase 1 — Script (mechanical):**
3. Run `~/.claude/plugins/cache/docbase/scripts/check-drift.sh PROJECT_ROOT DOC_ROOT ISSUES_DIR SOURCE_ROOTS "$CHANGED_FILES"` via Bash tool.
4. Parse JSON output.
5. Report mechanical findings: doc-drift count, undocumented count.

**Phase 2 — Sub-agent (conformance only):**
6. Filter `valid_impl_pairs` to only those with `"affected": true`. If none remain, skip sub-agent and report clean.
7. Spawn sub-agent with the affected pairs, the full git diff for changed files, and the resolved content of all doc and code files in the pairs.

   The sub-agent prompt must instruct:
   - For each pair (doc, code): read both files and the git diff for any changed file in the pair. Check conformance: API signatures, field names, data shapes, described behaviors.
   - Use the git diff to understand *what specifically changed* — this makes the conformance check precise rather than re-reading everything from scratch.
   - Sub-agent writes `conformance` issue files for divergences found.
   - Sub-agent auto-closes resolved `conformance` issues.
   - Sub-agent returns JSON: `{ "conformance_issues": N, "issues": [...] }`

**Phase 3 — Report:**
6. Merge script counts + sub-agent counts.
7. Present human-readable summary.
8. Output `docbase-result` JSON block:
```json
{
  "check": "code",
  "status": "pass"|"fail",
  "total": N,
  "issues": [...]
}
```

---

## Issue File Types

| Type | Written by | Command |
|---|---|---|
| `undeclared-reference` | `check-links.sh` | check-docs |
| `broken-link` | `check-links.sh` | check-docs |
| `semantic-conflict` | sub-agent | check-docs |
| `stale-reference` | sub-agent | check-docs |
| `doc-drift` | `check-drift.sh` | check-code |
| `undocumented` | `check-drift.sh` | check-code |
| `conformance` | sub-agent | check-code |

---

## CI/CD Implications

The script phase is fully standalone — no AI required. A CI/CD pipeline can:
1. Run `check-links.sh` directly, parse JSON, fail if `broken_links > 0`
2. Run `check-drift.sh` directly, parse JSON, fail if `doc_drift > 0`
3. Invoke `/docbase:check-docs` and `/docbase:check-code` for full semantic checks

The separation makes CI/CD cheaper: fast mechanical gate first, AI only when mechanical checks pass.
