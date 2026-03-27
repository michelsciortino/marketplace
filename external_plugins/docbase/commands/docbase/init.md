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
