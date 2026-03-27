---
description: "Check that source code correctly implements what the documentation specifies — conformance, doc-drift, and undocumented files. Writes issues to issues_dir and outputs a machine-readable JSON summary."
---
# /docbase:check-code

Check code↔doc conformance across the entire project.

## Steps

1. **Check prerequisites**
   - Verify `.docbase.json` exists in the current directory. If not, tell the user to run `/docbase:init` first.
   - Read `doc_root`, `source_roots`, and `issues_dir` from `.docbase.json`.

2. **Resolve paths**
   ```
   PROJECT_ROOT = current working directory (absolute path)
   DOC_ROOT = PROJECT_ROOT + "/" + doc_root
   ISSUES_DIR = PROJECT_ROOT + "/" + issues_dir
   SOURCE_ROOTS_JSON = the source_roots value from .docbase.json as a raw JSON object string
   TODAY = current date in YYYY-MM-DD format
   ```

3. **Resolve changed files** via Bash tool:
   ```bash
   git diff --name-only "origin/$(git rev-parse --abbrev-ref HEAD)..HEAD" 2>/dev/null \
     || git diff --name-only HEAD~1..HEAD 2>/dev/null \
     || echo ""
   ```
   Store the output as CHANGED_FILES (newline-separated relative paths, may be empty).
   If empty: all pairs will be treated as affected (full semantic sweep).

4. **Run check-drift.sh** via Bash tool (substitute resolved values — do not pass literal placeholders):
   ```bash
   ~/.claude/plugins/cache/docbase/scripts/check-drift.sh \
     "{PROJECT_ROOT}" "{DOC_ROOT}" "{ISSUES_DIR}" '{SOURCE_ROOTS_JSON}' "{CHANGED_FILES}"
   ```
   Parse the JSON output. Store `doc_drift`, `undocumented`, and `valid_impl_pairs`.

5. **Report mechanical findings** to the user:
   - If both counts are 0: "No mechanical drift issues found."
   - Otherwise: "Found {doc_drift} doc-drift issue(s) and {undocumented} undocumented file(s). Issue files written to {ISSUES_DIR}."

6. **Filter affected pairs**: from `valid_impl_pairs`, keep only those where `"affected": true`.
   - If none remain: tell the user "No affected pairs to check semantically." Skip to step 8.

7. **Spawn a sub-agent** using the Agent tool with this prompt (substitute all values before sending — no placeholders):
   ```
   You are the DocBase code↔doc conformance checker.

   Project root: {PROJECT_ROOT}
   Issues dir: {ISSUES_DIR}
   Today's date: {TODAY}

   Changed files since last push:
   {CHANGED_FILES — one per line, or "none" if empty}

   Doc↔code pairs to check (JSON array):
   {AFFECTED_PAIRS — the filtered valid_impl_pairs array, JSON}

   Each pair has: "doc" (doc file path relative to PROJECT_ROOT),
   "code" (code file path relative to PROJECT_ROOT), "affected" (always true).

   Your tasks:

   1. Run this command to get the git diff for changed files:
      git diff origin/$(git rev-parse --abbrev-ref HEAD)..HEAD -- {space-separated list of changed files}
      If no upstream: git diff HEAD~1..HEAD -- {files}

   2. For each pair (doc, code):
      a. Read both the doc file and the code file from disk.
         Doc files are at: {PROJECT_ROOT}/{doc}
         Code files are at: {PROJECT_ROOT}/{code}
      b. Review the git diff to understand exactly what changed in each file.
      c. Check conformance: do API function/method signatures match what the doc describes?
         Do field names and types match? Are the described behaviors present in the code?
      d. If they diverge, write a conformance issue file:
         Filename: {ISSUES_DIR}/{TODAY}-conformance-{hash}.md
         where hash = first 8 chars of md5("{doc}:{code}")
         ---
         type: conformance
         related_doc: "[{doc-basename}]({doc})"
         related_code: "[{code-basename}]({code})"
         created: {TODAY}
         ---
         ## Issue
         {one-line summary of the divergence}

         ## Detail
         What the doc specifies: ...
         What the code does: ...
         Divergence: ...

   3. For each existing issue file in {ISSUES_DIR} with type conformance:
      re-check if the conflict still exists. If resolved, delete the file.

   4. Return ONLY a JSON object — no other text:
      {
        "conformance_issues": <N>,
        "issues": [
          { "type": "conformance", "doc": "<path>", "code": "<path>", "issue": "<one-line summary>" }
        ]
      }
   ```

8. **Merge and present results** to the user:
   - Combine counts from script (doc_drift, undocumented) and sub-agent (conformance_issues).
   - If total is 0: "Code conformance check passed. No issues found."
   - Otherwise: list issues by type with file paths and one-line summaries.
   - Remind the user: issue files are in {ISSUES_DIR}.

9. **Output the JSON summary block**:
   ````
   ```docbase-result
   {
     "check": "code",
     "status": "pass or fail",
     "total": N,
     "issues": [...]
   }
   ```
   ````
