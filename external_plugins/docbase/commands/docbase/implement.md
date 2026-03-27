---
description: Find documentation sections with no corresponding implementation and implement selected ones, following the doc spec precisely.
---
# /docbase:implement

Find documentation sections with no corresponding implementation and implement selected ones.

## Steps

1. **Check prerequisites**
   - Verify `.docbase.json` exists. If not, tell the user to run `/docbase:init`.
   - Read `doc_root`, `source_roots`, and `issues_dir` from `.docbase.json`.

2. **Spawn a sub-agent** to find unimplemented doc sections:
   Prompt:
   ```
   Scan all .md files under <project_root>/<doc_root> for DocBase frontmatter.
   For each file, check its `implementation:` entries (values are markdown links `[text](path)` — extract the path from each):
     a. If `implementation:` is absent or empty: this doc has no implementation yet
     b. If `implementation:` lists files: check which ones do not yet exist on disk
   Return JSON:
   {
     "unimplemented_docs": [
       {
         "doc_path": "absolute/path/to/doc.md",
         "title": "first H1 heading in the file",
         "layer": "value of layer: frontmatter",
         "missing_files": ["path/that/doesnt/exist.ts"]
       }
     ]
   }
   Return ONLY the JSON.
   ```

3. **If no unimplemented docs found**: "All documented sections have corresponding implementation files."

4. **Present the list** to the user, grouped by layer. For each entry show:
   - Doc path
   - Title
   - Missing implementation files (if any declared)

5. **Ask**: "Which would you like me to implement? (Provide numbers, comma-separated, or 'all')"

6. **For each selected doc**, one at a time:
   - Read the full doc file
   - Tell the user: "I'm going to implement `<title>` based on `<doc_path>`. Here's my plan: ..."
   - Present a brief implementation plan (files to create, approach)
   - Ask: "Does this look right? Shall I proceed?"
   - On approval: implement, following the doc spec precisely
   - After implementation: update the doc's `implementation:` frontmatter with the new file paths as markdown links, e.g. `"[filename.ts](relative/path/to/file.ts)"`
   - Commit with message: `feat: implement <title> per <doc_path>`
