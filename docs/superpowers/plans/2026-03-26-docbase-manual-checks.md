# DocBase Manual Checks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all automatic DocBase hook triggers with two explicit manual commands (`/docbase:check-docs` and `/docbase:check-code`), each writing structured issue files and a machine-readable JSON summary.

**Architecture:** Delete the three hook files and the combined `check-consistency` command. Create two focused command files that each spawn a sub-agent and write results to `issues_dir`. Update `init.md` to remove all hook setup steps. Update `README.md` to reflect the new manual-only model.

**Tech Stack:** Claude Code slash commands (markdown), YAML frontmatter, Bun (frontmatter validation only)

---

## File Map

| Action | File |
|--------|------|
| Delete | `external_plugins/docbase/hooks/docbase-stop.sh` |
| Delete | `external_plugins/docbase/hooks/docbase-track-change.sh` |
| Delete | `external_plugins/docbase/hooks/docbase-post-commit.sh` |
| Delete | `external_plugins/docbase/commands/docbase/check-consistency.md` |
| Create | `external_plugins/docbase/commands/docbase/check-docs.md` |
| Create | `external_plugins/docbase/commands/docbase/check-code.md` |
| Modify | `external_plugins/docbase/commands/docbase/init.md` |
| Modify | `external_plugins/docbase/README.md` |

---

### Task 1: Delete hooks and old command

**Files:**
- Delete: `external_plugins/docbase/hooks/docbase-stop.sh`
- Delete: `external_plugins/docbase/hooks/docbase-track-change.sh`
- Delete: `external_plugins/docbase/hooks/docbase-post-commit.sh`
- Delete: `external_plugins/docbase/commands/docbase/check-consistency.md`

- [ ] **Step 1: Delete the four files**

```bash
rm external_plugins/docbase/hooks/docbase-stop.sh
rm external_plugins/docbase/hooks/docbase-track-change.sh
rm external_plugins/docbase/hooks/docbase-post-commit.sh
rm external_plugins/docbase/commands/docbase/check-consistency.md
```

- [ ] **Step 2: Verify the hooks directory only contains expected files**

Run: `ls external_plugins/docbase/hooks/`
Expected: empty output (no files remain)

- [ ] **Step 3: Commit**

```bash
git add -A external_plugins/docbase/hooks/ external_plugins/docbase/commands/docbase/check-consistency.md
git commit -m "feat(docbase): remove all automatic hook triggers and combined check command"
```

---

### Task 2: Create `/docbase:check-docs`

**Files:**
- Create: `external_plugins/docbase/commands/docbase/check-docs.md`

- [ ] **Step 1: Create the command file**

Full file content:

```markdown
---
description: Check all documentation files for cross-reference consistency — broken links, asymmetric related: entries, and semantic conflicts. Writes issues to issues_dir and outputs a machine-readable JSON summary.
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
   ```
   These resolved values must be substituted into the sub-agent prompt — do not pass literal placeholders.

3. **Spawn a sub-agent** using the Agent tool with this prompt (substitute resolved values for PROJECT_ROOT, DOC_ROOT, ISSUES_DIR):
   ```
   You are the DocBase doc cross-reference checker.

   Project root: {PROJECT_ROOT}
   Doc root: {DOC_ROOT}
   Issues dir: {ISSUES_DIR}

   Tasks:
   1. Find all .md files recursively under {DOC_ROOT} that have DocBase frontmatter
      (YAML block starting with --- containing at least one of: related, implementation, layer, status).
   2. For every file, extract its `related:` entries. Values are markdown links in the form
      `[text](path)` — extract the path portion from each.
      For each linked path:
      a. Resolve to absolute path: {PROJECT_ROOT} + "/" + path.
      b. Check if the file exists. If not: this is a broken-link issue.
      c. If it exists: read the file, extract its `related:` entries, and check if any of them
         point back to the current file. If not: this is an asymmetric-link issue.
   3. For every pair of related files that both exist, read both and check semantic consistency:
      - Do they agree on field names, types, API shapes, described behaviors?
      - Are there any direct contradictions?
      If yes: this is a semantic-conflict issue.
   4. For each new issue found, write a file to {ISSUES_DIR} named
      `<YYYY-MM-DD>-<type>-<slug>.md` where slug is a short kebab-case description.
      File format:
      ---
      type: broken-link
      related_doc: "[filename](relative/path/from/project/root)"
      created: YYYY-MM-DD
      ---
      ## Issue
      <one-line summary>

      ## Detail
      <full description of the problem>
   5. For each existing .md file in {ISSUES_DIR} whose `type` frontmatter is one of
      broken-link, asymmetric-link, semantic-conflict: re-check if the conflict still exists.
      If it is resolved, delete the file.
   6. Return ONLY a JSON object, no other text:
      {
        "check": "docs",
        "status": "pass",
        "total": 0,
        "issues": []
      }
      Set "status" to "fail" and populate "issues" if any open issues remain after this run.
      Each issue object:
      { "type": "broken-link"|"asymmetric-link"|"semantic-conflict", "file": "<absolute path>", "related_file": "<absolute path or empty>", "issue": "<description>" }
   ```

4. **Present findings** to the user:
   - If `total` is 0: "Doc consistency check passed. No issues found."
   - If `total` > 0: list issues grouped by type, showing file paths and one-line descriptions.
   - Tell the user where issue files were written: `{ISSUES_DIR}`.

5. **Output the JSON summary block** returned by the sub-agent, wrapped in a fenced code block labeled `docbase-result`:
   ````
   ```docbase-result
   { ... }
   ```
   ````
```

- [ ] **Step 2: Run frontmatter validation**

```bash
cd .github/scripts && bun validate-frontmatter.ts ../../external_plugins/docbase/commands/docbase/check-docs.md
```

Expected: no errors, exits 0.

- [ ] **Step 3: Commit**

```bash
git add external_plugins/docbase/commands/docbase/check-docs.md
git commit -m "feat(docbase): add /docbase:check-docs manual command"
```

---

### Task 3: Create `/docbase:check-code`

**Files:**
- Create: `external_plugins/docbase/commands/docbase/check-code.md`

- [ ] **Step 1: Create the command file**

Full file content:

```markdown
---
description: Check that source code correctly implements what the documentation specifies — conformance, doc-drift, and undocumented files. Writes issues to issues_dir and outputs a machine-readable JSON summary.
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
   SOURCE_ROOTS = source_roots object from .docbase.json (name → relative path pairs)
   ```
   These resolved values must be substituted into the sub-agent prompt — do not pass literal placeholders.

3. **Spawn a sub-agent** using the Agent tool with this prompt (substitute resolved values):
   ```
   You are the DocBase code↔doc conformance checker.

   Project root: {PROJECT_ROOT}
   Doc root: {DOC_ROOT}
   Source roots: {SOURCE_ROOTS}
   Issues dir: {ISSUES_DIR}

   Tasks:
   1. Find all .md files recursively under {DOC_ROOT} that have `implementation:` frontmatter.
      Values are markdown links `[text](path)` — extract the path from each.
   2. For each implementation path:
      a. Resolve to absolute: {PROJECT_ROOT} + "/" + path.
      b. If the file does not exist: this is a doc-drift issue (doc references a file that was deleted or never created).
      c. If the file exists: read both the doc and the source file. Check conformance:
         - API function/method signatures match what the doc describes
         - Field names and types match
         - Described behaviors are present in the code
         If they diverge: this is a conformance issue.
   3. Find all source files under each directory in {SOURCE_ROOTS}. For each source file:
      a. Check whether any doc's `implementation:` entries reference this file.
      b. If none do: this is an undocumented issue.
   4. For each new issue found, write a file to {ISSUES_DIR} named
      `<YYYY-MM-DD>-<type>-<slug>.md` where slug is a short kebab-case description.
      File format:
      ---
      type: conformance
      related_doc: "[filename](relative/path/from/project/root)"
      related_code: "[filename](relative/path/from/project/root)"
      created: YYYY-MM-DD
      ---
      ## Issue
      <one-line summary>

      ## Detail
      <full description of the divergence>
      Use type: doc-drift when related_code does not exist.
      Use type: undocumented when related_doc does not exist (omit related_doc field).
   5. For each existing .md file in {ISSUES_DIR} whose `type` frontmatter is one of
      conformance, doc-drift, undocumented: re-check if the conflict still exists.
      If it is resolved, delete the file.
   6. Return ONLY a JSON object, no other text:
      {
        "check": "code",
        "status": "pass",
        "total": 0,
        "issues": []
      }
      Set "status" to "fail" and populate "issues" if any open issues remain after this run.
      Each issue object:
      { "type": "conformance"|"doc-drift"|"undocumented", "doc": "<absolute path or empty>", "code": "<absolute path or empty>", "issue": "<description>" }
   ```

4. **Present findings** to the user:
   - If `total` is 0: "Code conformance check passed. No issues found."
   - If `total` > 0: list issues grouped by type (conformance, doc-drift, undocumented), showing file paths and one-line descriptions.
   - Tell the user where issue files were written: `{ISSUES_DIR}`.

5. **Output the JSON summary block** returned by the sub-agent, wrapped in a fenced code block labeled `docbase-result`:
   ````
   ```docbase-result
   { ... }
   ```
   ````
```

- [ ] **Step 2: Run frontmatter validation**

```bash
cd .github/scripts && bun validate-frontmatter.ts ../../external_plugins/docbase/commands/docbase/check-code.md
```

Expected: no errors, exits 0.

- [ ] **Step 3: Commit**

```bash
git add external_plugins/docbase/commands/docbase/check-code.md
git commit -m "feat(docbase): add /docbase:check-code manual command"
```

---

### Task 4: Update `/docbase:init`

**Files:**
- Modify: `external_plugins/docbase/commands/docbase/init.md`

Changes: remove the git repo prerequisite check, remove the post-commit hook installation step, update the final confirmation message.

- [ ] **Step 1: Overwrite init.md with updated content**

Full file content:

```markdown
---
description: Initialize DocBase for the current project — creates .docbase.json, updates .gitignore, and optionally scaffolds the doc directory structure.
---
# /docbase:init

Initialize DocBase for the current project. Run once at the project root.

## Steps

1. **Check prerequisites**
   - Verify `jq` is installed: `jq --version`. If missing, tell the user to install it (`brew install jq` on macOS).
   - Verify `claude` CLI is available: `claude --version`.

2. **Gather configuration** (ask one at a time)
   - What is the documentation root directory? (suggest: `docs/`)
   - What source code directories exist, and what are their names?
     Collect name→path pairs. Example: `app → app/`, `backend → backend/`, `infrastructure → infrastructure/`.
     Ask "Any more source roots?" until the user is done.
   - Where should issue files be stored? (suggest: `.issues/`)

3. **Write `.docbase.json`** at the project root:
   ```json
   {
     "doc_root": "<doc_root>",
     "source_roots": {
       "<name>": "<path>",
       ...
     },
     "issues_dir": "<issues_dir>"
   }
   ```

4. **Update `.gitignore`**
   - Check if `.gitignore` exists. Create it if not.
   - Check if the issues_dir is already listed. If not, append it.

5. **Optionally scaffold doc_root**
   - Ask: "Would you like me to scaffold a directory structure under `<doc_root>` based on your source roots?"
   - If yes: create one subdirectory per source root name plus a `cross-cutting/` directory.
   - Create a `README.md` in each with minimal DocBase frontmatter template. Use markdown link format for `implementation:` and `related:` values, e.g. `"[filename.ts](relative/path/to/file.ts)"`.

6. **Confirm**
   - Print a summary of what was created/modified.
   - Suggest next steps: run `/docbase:check-docs` once documentation is written, and `/docbase:check-code` once code is implemented.
```

- [ ] **Step 2: Run frontmatter validation**

```bash
cd .github/scripts && bun validate-frontmatter.ts ../../external_plugins/docbase/commands/docbase/init.md
```

Expected: no errors, exits 0.

- [ ] **Step 3: Commit**

```bash
git add external_plugins/docbase/commands/docbase/init.md
git commit -m "feat(docbase): remove hook setup from init, update next-step suggestions"
```

---

### Task 5: Update README.md

**Files:**
- Modify: `external_plugins/docbase/README.md`

Changes: rewrite tagline and "How It Works" table, remove the hook installation section entirely, update the command table.

- [ ] **Step 1: Overwrite README.md with updated content**

Full file content:

```markdown
# DocBase

Documentation-driven development system for Claude Code. Every piece of code must have a corresponding documentation file. Documentation describes intent, API contracts, field names, and behaviors — run consistency checks manually when ready to verify.

## Concept

DocBase enforces docs as the single source of truth. When docs and code diverge, you find out explicitly — on your terms, not mid-session.

## Frontmatter Conventions

DocBase identifies managed docs by their YAML frontmatter:

```yaml
---
layer: services          # logical layer (api, services, data, etc.)
status: stable           # draft | stable | deprecated
implementation:          # source files this doc describes
  - "[meals.ts](backend/src/services/meals.ts)"
related:                 # cross-references to other doc files
  - "[Meals API](docs/api/meals.md)"
updated: 2026-03-26
---
```

## How It Works

Two manual commands run on demand. No automatic triggers.

| Command | What it checks |
|---|---|
| `/docbase:check-docs` | Cross-references between docs: broken links, asymmetric `related:` entries, semantic conflicts |
| `/docbase:check-code` | Code↔doc conformance: missing implementations, API drift, undocumented source files |

Both commands write issue files to `issues_dir` and output a machine-readable JSON summary — ready for CI/CD consumption.

Typical workflow: write docs → run `/docbase:check-docs` → implement code → run `/docbase:check-code`.

## Installation

### 1. Install the plugin

```sh
/plugin install docbase@michelsciortino-marketplace
```

### 2. Initialize a project

In your project root:

```
/docbase:init
```

This creates `.docbase.json` and updates `.gitignore`.

## Slash Commands

| Command | Description |
|---|---|
| `/docbase:init` | Initialize a project for DocBase |
| `/docbase:check-docs` | Check doc cross-reference consistency |
| `/docbase:check-code` | Check code↔doc conformance |
| `/docbase:issues` | List and manage open issues |
| `/docbase:implement` | Implement docs that have no code yet |

## Requirements

- `jq` (`brew install jq`)
- `claude` CLI (Claude Code)
```

- [ ] **Step 2: Commit**

```bash
git add external_plugins/docbase/README.md
git commit -m "docs(docbase): rewrite README for manual-only model, remove hook setup"
```

---

### Task 6: Validate all modified command files

- [ ] **Step 1: Run frontmatter validation across all docbase commands**

```bash
cd .github/scripts && bun validate-frontmatter.ts \
  ../../external_plugins/docbase/commands/docbase/check-docs.md \
  ../../external_plugins/docbase/commands/docbase/check-code.md \
  ../../external_plugins/docbase/commands/docbase/init.md \
  ../../external_plugins/docbase/commands/docbase/issues.md \
  ../../external_plugins/docbase/commands/docbase/implement.md
```

Expected: all files pass, exits 0.

- [ ] **Step 2: Confirm hooks directory is empty**

```bash
ls external_plugins/docbase/hooks/
```

Expected: empty output.

- [ ] **Step 3: Confirm all expected commands exist**

```bash
ls external_plugins/docbase/commands/docbase/
```

Expected: `check-code.md  check-docs.md  implement.md  init.md  issues.md`
(`check-consistency.md` must NOT be present)
