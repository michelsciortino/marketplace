---
description: "Check all documentation files for cross-reference consistency — broken links, undeclared references, and semantic conflicts. Writes issues to issues_dir and outputs a machine-readable JSON summary."
---
# /docbase:check-docs

Check documentation cross-reference consistency across the entire project.

## Steps

1. **Check prerequisites**
   - Verify `.docbase.json` exists in the current directory. If not, tell the user to run `/docbase:init` first.
   - Read `doc_root` and `issues_dir` from `.docbase.json`.

2. **Resolve paths**
   ```
   PROJECT_ROOT = current working directory (absolute path)
   DOC_ROOT = PROJECT_ROOT + "/" + doc_root
   ISSUES_DIR = PROJECT_ROOT + "/" + issues_dir
   TODAY = current date in YYYY-MM-DD format
   ```

3. **Resolve changed files** via Bash tool:
   ```bash
   git diff --name-only "origin/$(git rev-parse --abbrev-ref HEAD)..HEAD" 2>/dev/null \
     || git diff --name-only HEAD~1..HEAD 2>/dev/null \
     || echo ""
   ```
   Store the output as CHANGED_FILES (newline-separated relative paths, may be empty).
   If empty: all edges will be treated as affected (full semantic sweep).

4. **Run check-links.sh** via Bash tool (substitute resolved values — do not pass literal placeholders):
   ```bash
   ~/.claude/plugins/cache/docbase/scripts/check-links.sh \
     "{PROJECT_ROOT}" "{DOC_ROOT}" "{ISSUES_DIR}" "{CHANGED_FILES}"
   ```
   Parse the JSON output. Store `undeclared_references`, `broken_links`, and `valid_edges`.

5. **Report mechanical findings** to the user:
   - If both counts are 0: "No mechanical link issues found."
   - Otherwise: "Found {undeclared_references} undeclared reference(s) and {broken_links} broken link(s). Issue files written to {ISSUES_DIR}."

6. **Filter affected edges**: from `valid_edges`, keep only those where `"affected": true`.
   - If none remain: tell the user "No affected edges to check semantically." Skip to step 8.

7. **Spawn a sub-agent** using the Agent tool with this prompt (substitute all values before sending — no placeholders):
   ```
   You are the DocBase semantic consistency checker.

   Project root: {PROJECT_ROOT}
   Issues dir: {ISSUES_DIR}
   Today's date: {TODAY}

   Changed files since last push:
   {CHANGED_FILES — one per line, or "none" if empty}

   Directed edges to check semantically (JSON array):
   {AFFECTED_EDGES — the filtered valid_edges array, JSON}

   Each edge has: "from" (source doc), "to" (referenced doc), "cycle" (boolean),
   "affected" (always true at this point).

   Your tasks:

   1. Run this command to get the git diff for changed files:
      git diff origin/$(git rev-parse --abbrev-ref HEAD)..HEAD -- {space-separated list of changed doc files}
      If no upstream: git diff HEAD~1..HEAD -- {files}

   2. For each edge A → B in the edges array:
      a. Read both files A and B from disk.
      b. Review the git diff to understand exactly what changed in each file.
      c. Check semantic consistency: does A's content that references B still hold given
         B's current content? Look for: field name mismatches, type conflicts, API shape
         differences, contradictory described behaviors.
      d. Transitive reference check: if B has changed and B now references a new file C
         (i.e. B→C is a new link), and the content A was depending on appears to have moved
         from B to C, write a stale-reference issue:
         "A references B for [topic], which appears to have moved to C via B→C.
          Consider whether A should directly reference C, or whether the transitive
          chain A→B→C is sufficient for readers." The human decides — do not auto-update.
      e. For cycle edges (cycle: true): check both directions independently.
         If content diverges, write a semantic-conflict issue with this note:
         "This is a cyclic reference (A→B and B→A). Decide which document is authoritative
          and update the other." If the cycle edges are consistent, write no issue.

   3. For each conflict found, write an issue file:
      Filename: {ISSUES_DIR}/{TODAY}-{type}-{hash}.md
      where hash = first 8 chars of md5("{from}:{to}")

      For semantic-conflict:
      ---
      type: semantic-conflict
      related_doc: "[{from-basename}]({from})"
      created: {TODAY}
      ---
      ## Issue
      {one-line summary}

      ## Detail
      What {from} says: ...
      What {to} says: ...
      Conflict: ...

      For stale-reference:
      ---
      type: stale-reference
      related_doc: "[{from-basename}]({from})"
      created: {TODAY}
      ---
      ## Issue
      {from} references {to} for [topic], which has moved to {C}

      ## Detail
      Explain what moved, what the transitive chain is, and what the human needs to decide.

   4. For each existing issue file in {ISSUES_DIR} with type semantic-conflict or
      stale-reference: re-check if the conflict still exists in the current files.
      If resolved, delete the file.

   5. Return ONLY a JSON object — no other text:
      {
        "semantic_conflicts": <N>,
        "stale_references": <N>,
        "issues": [
          { "type": "semantic-conflict"|"stale-reference", "from": "<path>", "to": "<path>", "issue": "<one-line summary>" }
        ]
      }
   ```

8. **Merge and present results** to the user:
   - Combine counts from script (undeclared_references, broken_links) and sub-agent (semantic_conflicts, stale_references).
   - If total is 0: "Doc consistency check passed. No issues found."
   - Otherwise: list issues by type with file paths and one-line summaries.
   - Remind the user: issue files are in {ISSUES_DIR}.

9. **Output the JSON summary block**:
   ````
   ```docbase-result
   {
     "check": "docs",
     "status": "pass or fail",
     "total": N,
     "issues": [...]
   }
   ```
   ````
