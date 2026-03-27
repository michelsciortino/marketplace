# DocBase POC Test Design

**Date:** 2026-03-26
**Scope:** Repeatable integration test for the DocBase plugin's markdown link frontmatter format

---

## Goal

Validate that the DocBase hooks and commands correctly parse `[text](path)` markdown links from `implementation:` and `related:` YAML frontmatter fields, replacing the old plain-text path format.

---

## Structure

```
/Users/michelsciortino/DEV/claude-plugins/   (repo root, gitignored)
└── tests/
    └── docbase/
        ├── run.sh              # test runner
        └── fixtures/
            ├── meals.md        # doc with implementation: markdown link
            ├── logs.md         # doc with related: markdown link
            └── meals.ts        # source file
```

`tests/` is added to `.gitignore` and never committed to the marketplace repo.

---

## Fixtures

### `fixtures/meals.md`
```yaml
---
layer: services
status: stable
implementation:
  - "[meals.ts](backend/src/services/meals.ts)"
related:
  - "[Logs API](docs/services/logs.md)"
updated: 2026-03-26
---
# Meals Service
Handles meal CRUD operations.
```

### `fixtures/logs.md`
```yaml
---
layer: services
status: stable
implementation:
  - "[logs.ts](backend/src/handlers/logs.ts)"
related:
  - "[Meals Service](docs/services/meals.md)"
updated: 2026-03-26
---
# Logs Handler
Returns application logs.
```

### `fixtures/meals.ts`
```typescript
export function getMeals() { return []; }
```

---

## Test Cases

| # | Name | Setup | Hook | Asserts |
|---|---|---|---|---|
| 1 | `documented_file` | `meals.ts` committed, `meals.md` links it via markdown link | `docbase-post-commit.sh` | no issue file created |
| 2 | `undocumented_file` | `logs.ts` committed, no doc references it | `docbase-post-commit.sh` | issue file created with `type: undocumented` |
| 3 | `broken_related_link` | `meals.md` has `related:` pointing to nonexistent `logs.md` | `docbase-stop.sh` (via stdin JSON) | hook exits 2, stderr contains link error |
| 4 | `symmetric_related_links` | `meals.md` ↔ `logs.md` both reference each other, both files exist | `docbase-stop.sh` | hook exits 0, no issues |

---

## Mechanics

### Per-test isolation
Each test function:
1. Creates a fresh temp dir (`mktemp -d`)
2. `git init` + initial empty commit
3. Copies the relevant fixture files into place
4. Commits source files (to trigger `docbase-post-commit.sh`) or writes doc files (to trigger `docbase-stop.sh`)
5. Runs the hook
6. Asserts via `grep` / exit code
7. Removes the temp dir

### Claude model override
The test runner creates a `claude` shim at the start and prepends it to `PATH`:

```bash
mkdir -p /tmp/docbase_test_bin
cat > /tmp/docbase_test_bin/claude << 'SHIM'
#!/usr/bin/env bash
exec "$(which -a claude | grep -v "$0" | head -1)" --model claude-haiku-4-5-20251001 "$@"
SHIM
chmod +x /tmp/docbase_test_bin/claude
export PATH="/tmp/docbase_test_bin:$PATH"
```

This ensures all `claude -p` calls inside the hooks use Haiku, with no modification to the hooks themselves.

### Hook invocation
- **`docbase-post-commit.sh`** — invoked as the git `post-commit` hook after a real `git commit` in the temp repo
- **`docbase-stop.sh`** — invoked directly with a crafted JSON payload via stdin (simulating the Claude Code Stop hook input)

### Assertions
```bash
assert_file_exists()  # checks a path exists
assert_file_absent()  # checks a path does not exist
assert_contains()     # grep -q on a file
assert_exit()         # checks last command's exit code
```

### Output
```
[PASS] documented_file
[FAIL] undocumented_file — expected issue file, none found
[PASS] broken_related_link
[PASS] symmetric_related_links

1 failed
```

Exit code 0 if all pass, 1 if any fail.

### Hook source
Hooks are loaded from `DOCBASE_HOOKS_DIR`, defaulting to:
1. `~/.claude/plugins/cache/docbase/hooks/` (installed plugin)
2. `<repo_root>/external_plugins/docbase/hooks/` (local dev fallback)

---

## Out of Scope

- Testing `/docbase:init`, `/docbase:check-consistency`, `/docbase:issues`, `/docbase:implement` commands (these are slash commands run interactively by Claude Code, not directly invokable shell scripts)
- CI integration (this is a local dev POC only)
