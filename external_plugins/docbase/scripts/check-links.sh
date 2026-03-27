#!/usr/bin/env bash
# check-links.sh — DocBase mechanical link checker
# Backs /docbase:check-docs
# Usage: check-links.sh PROJECT_ROOT DOC_ROOT ISSUES_DIR [CHANGED_FILES]
#
# CHANGED_FILES: newline-separated relative paths (to PROJECT_ROOT) of changed files.
#                Pass empty string or omit for full sweep (all edges marked affected).
#
# Path conventions:
#   related: frontmatter paths  → relative to PROJECT_ROOT
#   body markdown links         → relative to PROJECT_ROOT (same convention)
#
# Outputs JSON to stdout.

set -euo pipefail

PROJECT_ROOT="${1:?PROJECT_ROOT required}"
DOC_ROOT="${2:?DOC_ROOT required}"
ISSUES_DIR="${3:?ISSUES_DIR required}"
CHANGED_FILES="${4:-}"

TODAY=$(date +%Y-%m-%d)
UNDECLARED_COUNT=0
BROKEN_COUNT=0

mkdir -p "$ISSUES_DIR"

# ─── temp storage (bash 3.2 compatible) ─────────────────────────────────────

TMPDIR_STATE=$(mktemp -d)
trap 'rm -rf "$TMPDIR_STATE"' EXIT

# Emulate associative arrays via temp files:
#   current_issues/  — one file per issue filename (presence = registered)
#   fm_targets/      — one file per source, containing space-sep abs fm targets
#   all_targets/     — one file per source, containing space-sep abs all targets
mkdir -p "$TMPDIR_STATE/current_issues" "$TMPDIR_STATE/fm_targets" "$TMPDIR_STATE/all_targets" "$TMPDIR_STATE/link_lines"

# Safe key: encode a filepath to a filesystem-safe name using md5/md5sum
encode_key() {
  if command -v md5sum &>/dev/null; then
    printf '%s' "$1" | md5sum | cut -c1-32
  else
    printf '%s' "$1" | md5 -q | cut -c1-32
  fi
}

# CURRENT_ISSUE_FILES operations
register_issue_file() {
  local k; k=$(encode_key "$1")
  touch "$TMPDIR_STATE/current_issues/$k"
  # Store original path so we can compare later
  printf '%s\n' "$1" > "$TMPDIR_STATE/current_issues/${k}.path"
}

is_issue_file_registered() {
  # $1 = issue filename path
  local k; k=$(encode_key "$1")
  [[ -f "$TMPDIR_STATE/current_issues/$k" ]]
}

# FM_TARGETS / ALL_TARGETS operations
set_fm_targets() {
  local k; k=$(encode_key "$1")
  printf '%s\n' "$2" > "$TMPDIR_STATE/fm_targets/$k"
}

get_fm_targets() {
  local k; k=$(encode_key "$1")
  if [[ -f "$TMPDIR_STATE/fm_targets/$k" ]]; then
    cat "$TMPDIR_STATE/fm_targets/$k"
  fi
}

set_all_targets() {
  local k; k=$(encode_key "$1")
  printf '%s\n' "$2" > "$TMPDIR_STATE/all_targets/$k"
}

get_all_targets() {
  local k; k=$(encode_key "$1")
  if [[ -f "$TMPDIR_STATE/all_targets/$k" ]]; then
    cat "$TMPDIR_STATE/all_targets/$k"
  fi
}

# link_lines: source_abs:target_abs → line number where the link appears
set_link_line() {
  local k; k=$(encode_key "$1:$2")
  printf '%s\n' "$3" > "$TMPDIR_STATE/link_lines/$k"
}

get_link_line() {
  local k; k=$(encode_key "$1:$2")
  if [[ -f "$TMPDIR_STATE/link_lines/$k" ]]; then
    cat "$TMPDIR_STATE/link_lines/$k"
  fi
}

# ─── helpers ────────────────────────────────────────────────────────────────

# Returns 0 if the file has DocBase frontmatter (any of: related, implementation, layer, status)
has_docbase_frontmatter() {
  awk '
    BEGIN { block=0; found=0 }
    /^---/ { block++; if (block==2) exit }
    block==1 && /^(related|implementation|layer|status):/ { found=1; exit }
    END { exit (found ? 0 : 1) }
  ' "$1"
}

# Extract paths from related: frontmatter block.
# Paths are relative to PROJECT_ROOT (docbase convention).
# Outputs: linenum TAB path
extract_frontmatter_links() {
  local file="$1"
  local block=0 in_related=0 linenum=0
  while IFS= read -r line; do
    linenum=$((linenum + 1))
    if [[ "$line" == "---" ]]; then
      block=$((block + 1))
      [[ $block -eq 2 ]] && break
      continue
    fi
    [[ $block -eq 0 ]] && continue
    if [[ "$line" =~ ^related:[[:space:]]*$ ]]; then
      in_related=1; continue
    fi
    if [[ $in_related -eq 1 ]]; then
      if [[ "$line" =~ ^[[:space:]]+-[[:space:]] ]]; then
        path=$(printf '%s\n' "$line" | sed -n 's/.*\[.*\](\([^)]*\)).*/\1/p')
        [[ -n "$path" ]] && printf '%d\t%s\n' "$linenum" "$path"
      elif [[ "$line" =~ ^[a-zA-Z] ]]; then
        in_related=0
      fi
    fi
  done < "$file"
}

# Extract body markdown links pointing to .md files.
# Links are PROJECT_ROOT-relative (same convention as frontmatter).
# Only returns links that resolve within DOC_ROOT.
# Outputs: linenum TAB path
extract_body_links() {
  local file="$1"
  local block=0 linenum=0
  while IFS= read -r line; do
    linenum=$((linenum + 1))
    if [[ "$line" == "---" ]]; then
      block=$((block + 1)); continue
    fi
    [[ $block -lt 2 ]] && continue
    # Extract all markdown link targets ending in .md from this line using grep+sed
    # grep returns 1 on no match; suppress that to avoid pipefail termination
    while IFS= read -r path; do
      [[ -n "$path" ]] && printf '%d\t%s\n' "$linenum" "$path"
    done < <(printf '%s\n' "$line" | /usr/bin/grep -o '\[[^]]*\]([^)]*)' | /usr/bin/sed -n 's/.*(\([^)]*\.md[^)]*\))/\1/p' || true)
  done < "$file"
}

# Resolve a PROJECT_ROOT-relative path to absolute.
# Strips a leading / from the path to avoid double-slash when paths are written as /docs/...
resolve_from_root() {
  local path="${1#/}"
  echo "$PROJECT_ROOT/$path"
}

# Resolve a file-relative path to absolute, then normalize.
resolve_from_file() {
  local source_file="$1" link_path="$2"
  local source_dir; source_dir=$(dirname "$source_file")
  local abs="$source_dir/$link_path"
  # Normalize: collapse .. and .
  echo "$abs" | awk -F/ 'BEGIN{OFS="/"} {
    n=0
    for(i=1;i<=NF;i++){
      if($i==".."){if(n>0)n--}
      else if($i!="."&&$i!=""){a[n++]=$i}
    }
    printf "/"
    for(i=0;i<n;i++){printf a[i]; if(i<n-1)printf "/"}
    printf "\n"
  }'
}

# Returns true if the path is within DOC_ROOT
is_in_doc_root() {
  [[ "$1" == "$DOC_ROOT"* ]]
}

# Generate a deterministic issue filename.
# key: unique string identifying this issue (e.g. "source:target")
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

# Write an issue file only if it doesn't already exist.
# Also registers the filename in CURRENT_ISSUE_FILES.
# Args: filename type related_doc line_number summary detail
#   line_number: pass empty string if unknown
write_issue() {
  local filename="$1" type="$2" related_doc="$3" line_number="$4" summary="$5" detail="$6"
  register_issue_file "$filename"
  [[ -f "$filename" ]] && return
  {
    echo "---"
    echo "type: $type"
    echo "related_doc: \"$related_doc\""
    [[ -n "$line_number" ]] && echo "line_number: $line_number"
    echo "created: $TODAY"
    echo "---"
    echo "## Issue"
    echo "$summary"
    echo ""
    echo "## Detail"
    echo "$detail"
  } > "$filename"
}

# ─── pass 1: collect all links ──────────────────────────────────────────────

DOCBASE_FILES=()
while IFS= read -r f; do
  has_docbase_frontmatter "$f" && DOCBASE_FILES+=("$f")
done < <(find "$DOC_ROOT" -name "*.md" -type f | sort)

for file in "${DOCBASE_FILES[@]}"; do
  rel_source="${file#$PROJECT_ROOT/}"
  fm=()
  all=()

  # Frontmatter links (PROJECT_ROOT-relative)
  while IFS=$'\t' read -r linenum path; do
    [[ -z "$path" ]] && continue
    abs=$(resolve_from_root "$path")
    is_in_doc_root "$abs" || continue
    fm+=("$abs")
    all+=("$abs")
    set_link_line "$file" "$abs" "$linenum"
  done < <(extract_frontmatter_links "$file")

  # Body links (PROJECT_ROOT-relative, same convention as frontmatter)
  while IFS=$'\t' read -r linenum path; do
    [[ -z "$path" ]] && continue
    abs=$(resolve_from_root "$path")
    is_in_doc_root "$abs" || continue

    # Check if already in frontmatter
    in_fm=false
    for t in "${fm[@]:-}"; do [[ "$t" == "$abs" ]] && in_fm=true && break; done

    if ! $in_fm; then
      rel_target="${abs#$PROJECT_ROOT/}"
      fname=$(issue_filename "undeclared-reference" "${rel_source}:${rel_target}")
      write_issue "$fname" "undeclared-reference" "$rel_source" "$linenum" \
        "Body link to $rel_target not declared in related: frontmatter (line $linenum)" \
        "The document $rel_source line $linenum contains a markdown link to $rel_target in its body, but $rel_target is not listed in the related: frontmatter. Add it to make the reference explicit and discoverable."
      UNDECLARED_COUNT=$((UNDECLARED_COUNT + 1))
    fi
    all+=("$abs")
    set_link_line "$file" "$abs" "$linenum"
  done < <(extract_body_links "$file")

  set_fm_targets "$file" "${fm[*]:-}"
  set_all_targets "$file" "${all[*]:-}"
done

# ─── pass 2: check broken links, build valid edges ──────────────────────────

VALID_EDGES="[]"

for file in "${DOCBASE_FILES[@]}"; do
  rel_source="${file#$PROJECT_ROOT/}"
  all_targets_val=$(get_all_targets "$file")
  for target in $all_targets_val; do
    rel_target="${target#$PROJECT_ROOT/}"

    if [[ ! -f "$target" ]]; then
      linenum=$(get_link_line "$file" "$target")
      fname=$(issue_filename "broken-link" "${rel_source}:${rel_target}")
      write_issue "$fname" "broken-link" "$rel_source" "$linenum" \
        "Broken link: $rel_target does not exist${linenum:+ (line $linenum)}" \
        "The document $rel_source${linenum:+ line $linenum} references $rel_target, but that file does not exist."
      BROKEN_COUNT=$((BROKEN_COUNT + 1))
      continue
    fi

    # Determine if affected by recent changes
    affected=false
    if [[ -z "$CHANGED_FILES" ]]; then
      affected=true
    else
      while IFS= read -r changed; do
        [[ -z "$changed" ]] && continue
        if [[ "$PROJECT_ROOT/$changed" == "$file" || "$PROJECT_ROOT/$changed" == "$target" ]]; then
          affected=true; break
        fi
      done <<< "$CHANGED_FILES"
    fi

    # Detect cycle: does target also link back to source?
    cycle=false
    target_all=$(get_all_targets "$target")
    for back in $target_all; do
      [[ "$back" == "$file" ]] && cycle=true && break
    done

    VALID_EDGES=$(echo "$VALID_EDGES" | jq \
      --arg from "$rel_source" \
      --arg to "$rel_target" \
      --argjson cycle "$cycle" \
      --argjson affected "$affected" \
      '. + [{"from":$from,"to":$to,"cycle":$cycle,"affected":$affected}]')
  done
done

# ─── auto-close resolved issues ─────────────────────────────────────────────

for issue_file in "$ISSUES_DIR"/*.md; do
  [[ -f "$issue_file" ]] || continue
  itype=$(awk '/^---/{b++;if(b==2)exit} b==1&&/^type:/{print $2}' "$issue_file" | tr -d '"')
  [[ "$itype" == "undeclared-reference" || "$itype" == "broken-link" ]] || continue
  if ! is_issue_file_registered "$issue_file"; then
    rm -f "$issue_file"
  fi
done

# ─── output ─────────────────────────────────────────────────────────────────

jq -n \
  --argjson undeclared "$UNDECLARED_COUNT" \
  --argjson broken "$BROKEN_COUNT" \
  --argjson edges "$VALID_EDGES" \
  '{"undeclared_references":$undeclared,"broken_links":$broken,"valid_edges":$edges}'
