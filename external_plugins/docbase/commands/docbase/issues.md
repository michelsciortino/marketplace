---
description: List and manage open DocBase issues for the current project — shows issues grouped by type and guides resolution.
---
# /docbase:issues

List and manage open DocBase issues for the current project.

## Steps

1. **Check prerequisites**
   - Verify `.docbase.json` exists. If not, tell the user to run `/docbase:init`.
   - Read `issues_dir` from `.docbase.json`.
   - Check if `<issues_dir>` exists and contains `.md` files. If empty or absent: "No open issues."

2. **Spawn a sub-agent** to read and summarize all issue files:
   Prompt:
   ```
   Read all .md files in <project_root>/<issues_dir>.
   For each file, extract:
     - filename
     - type (from frontmatter)
     - related_doc (from frontmatter — value is a markdown link `[text](path)`, extract the path)
     - related_code (from frontmatter — value is a markdown link `[text](path)`, extract the path)
     - created (from frontmatter)
     - first line of the ## Issue section (summary)
   Return JSON array:
   [{ "filename": "...", "type": "...", "related_doc": "...", "related_code": "...", "created": "...", "summary": "..." }]
   Return ONLY the JSON.
   ```

3. **Present a grouped summary** to the user:
   - Group by type: crossref, conformance, undocumented, doc-drift
   - For each issue: show type, affected files, one-line summary
   - Show total count

4. **Ask the user**: "Which issue would you like to address? (Provide a number, or say 'all')"

5. **For each selected issue**:
   - Read the full issue file
   - Present it to the user
   - Ask: "How would you like to resolve this? I can help update the doc, fix the code, or explain the options."
