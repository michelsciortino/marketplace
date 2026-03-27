#!/usr/bin/env bash
# check-drift.sh — DocBase mechanical doc↔code drift checker
# Backs /docbase:check-code
# Usage: check-drift.sh PROJECT_ROOT DOC_ROOT ISSUES_DIR SOURCE_ROOTS [CHANGED_FILES]
#
# SOURCE_ROOTS: JSON object, e.g. '{"backend":"backend/src","frontend":"frontend/src"}'
#               Values are relative to PROJECT_ROOT.
# CHANGED_FILES: newline-separated relative paths (to PROJECT_ROOT) of changed files.
#                Pass empty string or omit for full sweep.
#
# implementation: frontmatter paths are relative to PROJECT_ROOT.
# Outputs JSON to stdout.

set -euo pipefail

PROJECT_ROOT="${1:?PROJECT_ROOT required}"
DOC_ROOT="${2:?DOC_ROOT required}"
ISSUES_DIR="${3:?ISSUES_DIR required}"
SOURCE_ROOTS="${4:?SOURCE_ROOTS required}"
CHANGED_FILES="${5:-}"

TODAY=$(date +%Y-%m-%d)
DOC_DRIFT_COUNT=0
UNDOCUMENTED_COUNT=0

mkdir -p "$ISSUES_DIR"

# ─── temp storage (bash 3.2 compatible) ─────────────────────────────────────

TMPDIR_STATE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_STATE"' EXIT

mkdir -p "$TMPDIR_STATE/current_issues" "$TMPDIR_STATE/documented_files"

encode_key() {
  if command -v md5sum &>/dev/null; then
    printf '%s' "$1" | md5sum | cut -c1-32
  else
    printf '%s' "$1" | md5 -q | cut -c1-32
  fi
}

register_issue_file() {
  local k; k=$(encode_key "$1")
  touch "$TMPDIR_STATE/current_issues/$k"
  printf '%s\n' "$1" > "$TMPDIR_STATE/current_issues/${k}.path"
}

is_issue_file_registered() {
  local k; k=$(encode_key "$1")
  [[ -f "$TMPDIR_STATE/current_issues/$k" ]]
}

mark_documented() {
  local k; k=$(encode_key "$1")
  touch "$TMPDIR_STATE/documented_files/$k"
}

is_documented() {
  local k; k=$(encode_key "$1")
  [[ -f "$TMPDIR_STATE/documented_files/$k" ]]
}

# ─── helpers ────────────────────────────────────────────────────────────────

# Extract paths from implementation: frontmatter block.
# Paths are relative to PROJECT_ROOT.
extract_implementation_links() {
  local file="$1"
  local block=0 in_impl=0
  while IFS= read -r line; do
    if [[ "$line" == "---" ]]; then
      block=$((block + 1))
      [[ $block -eq 2 ]] && break
      continue
    fi
    [[ $block -eq 0 ]] && continue
    if [[ "$line" =~ ^implementation:[[:space:]]*$ ]]; then
      in_impl=1; continue
    fi
    if [[ $in_impl -eq 1 ]]; then
      if [[ "$line" =~ ^[[:space:]]+-[[:space:]] ]]; then
        printf '%s\n' "$line" | /usr/bin/sed -n 's/.*\[.*\](\([^)]*\)).*/\1/p'
      elif [[ "$line" =~ ^[a-zA-Z] ]]; then
        in_impl=0
      fi
    fi
  done < "$file"
}

# Check if file has implementation: frontmatter
has_implementation_frontmatter() {
  awk '
    BEGIN{block=0;found=0}
    /^---/{block++;if(block==2)exit}
    block==1&&/^implementation:/{found=1;exit}
    END{exit(found?0:1)}
  ' "$1"
}

issue_filename() {
  local type="$1" key="$2"
  local hash
  if command -v md5sum &>/dev/null; then
    hash=$(printf '%s' "$key" | md5sum | cut -c1-8)
  else
    hash=$(printf '%s' "$key" | md5 -q | cut -c1-8)
  fi
  echo "$ISSUES_DIR/${type}-${hash}.md"
}

write_issue() {
  local filename="$1" type="$2" related_doc="${3:-}" related_code="${4:-}" summary="$5" detail="$6"
  register_issue_file "$filename"
  [[ -f "$filename" ]] && return
  {
    echo "---"
    echo "type: $type"
    [[ -n "$related_doc" ]]  && echo "related_doc: \"$related_doc\""
    [[ -n "$related_code" ]] && echo "related_code: \"$related_code\""
    echo "created: $TODAY"
    echo "---"
    echo "## Issue"
    echo "$summary"
    echo ""
    echo "## Detail"
    echo "$detail"
  } > "$filename"
}

is_affected() {
  local f1="$1" f2="${2:-}"
  [[ -z "$CHANGED_FILES" ]] && echo "true" && return
  while IFS= read -r changed; do
    [[ -z "$changed" ]] && continue
    local abs="$PROJECT_ROOT/$changed"
    if [[ "$abs" == "$f1" ]] || [[ -n "$f2" && "$abs" == "$f2" ]]; then
      echo "true"; return
    fi
  done <<< "$CHANGED_FILES"
  echo "false"
}

# ─── scan docs ──────────────────────────────────────────────────────────────

VALID_IMPL_PAIRS="[]"

while IFS= read -r doc_file; do
  has_implementation_frontmatter "$doc_file" || continue
  rel_doc="${doc_file#$PROJECT_ROOT/}"

  while IFS= read -r impl_path; do
    [[ -z "$impl_path" ]] && continue
    abs_impl="$PROJECT_ROOT/$impl_path"

    if [[ ! -f "$abs_impl" ]]; then
      fname=$(issue_filename "doc-drift" "${rel_doc}:${impl_path}")
      write_issue "$fname" "doc-drift" "$rel_doc" "" \
        "Doc-drift: $impl_path does not exist" \
        "The document $rel_doc lists $impl_path in its implementation: frontmatter, but that file does not exist. Either create the file or remove it from the frontmatter."
      DOC_DRIFT_COUNT=$((DOC_DRIFT_COUNT + 1))
    else
      mark_documented "$abs_impl"
      affected=$(is_affected "$doc_file" "$abs_impl")
      VALID_IMPL_PAIRS=$(echo "$VALID_IMPL_PAIRS" | jq \
        --arg doc "$rel_doc" \
        --arg code "$impl_path" \
        --argjson affected "$affected" \
        '. + [{"doc":$doc,"code":$code,"affected":$affected}]')
    fi
  done < <(extract_implementation_links "$doc_file")
done < <(find "$DOC_ROOT" -name "*.md" -type f | sort)

# ─── scan source roots ──────────────────────────────────────────────────────

while IFS= read -r source_dir_rel; do
  [[ -z "$source_dir_rel" ]] && continue
  abs_source_dir="$PROJECT_ROOT/$source_dir_rel"
  [[ -d "$abs_source_dir" ]] || continue

  while IFS= read -r code_file; do
    if is_documented "$code_file"; then continue; fi
    rel_code="${code_file#$PROJECT_ROOT/}"
    fname=$(issue_filename "undocumented" "$rel_code")
    write_issue "$fname" "undocumented" "" "$rel_code" \
      "Undocumented: $rel_code has no corresponding doc" \
      "The source file $rel_code is not referenced by any document's implementation: frontmatter. Add documentation for it or exclude this directory from source_roots."
    UNDOCUMENTED_COUNT=$((UNDOCUMENTED_COUNT + 1))
  done < <(find "$abs_source_dir" -type f | sort)
done < <(echo "$SOURCE_ROOTS" | jq -r '.[]')

# ─── auto-close resolved issues ─────────────────────────────────────────────

for issue_file in "$ISSUES_DIR"/*.md; do
  [[ -f "$issue_file" ]] || continue
  itype=$(awk '/^---/{b++;if(b==2)exit} b==1&&/^type:/{print $2}' "$issue_file" | tr -d '"')
  [[ "$itype" == "doc-drift" || "$itype" == "undocumented" ]] || continue
  if ! is_issue_file_registered "$issue_file"; then
    rm -f "$issue_file"
  fi
done

# ─── output ─────────────────────────────────────────────────────────────────

jq -n \
  --argjson drift "$DOC_DRIFT_COUNT" \
  --argjson undocumented "$UNDOCUMENTED_COUNT" \
  --argjson pairs "$VALID_IMPL_PAIRS" \
  '{"doc_drift":$drift,"undocumented":$undocumented,"valid_impl_pairs":$pairs}'
