#!/usr/bin/env bash
#
# bump-version.sh — bump version numbers across all declared files
# (JSON fields or "{version}" text patterns, see .version-bump.json),
# with drift detection and repo-wide audit for missed files.
#
# Usage:
#   bump-version.sh <new-version>   Bump all declared files to new version
#   bump-version.sh --check         Report current versions (detect drift)
#   bump-version.sh --audit         Check + grep repo for old version strings
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG="$REPO_ROOT/.version-bump.json"

if [[ ! -f "$CONFIG" ]]; then
  echo "error: .version-bump.json not found at $CONFIG" >&2
  exit 1
fi

# --- helpers ---

# Read a dotted field path from a JSON file.
# Handles both simple ("version") and nested ("plugins.0.version") paths.
read_json_field() {
  local file="$1" field="$2"
  # Convert dot-path to jq path: "plugins.0.version" -> .plugins[0].version
  local jq_path
  jq_path=$(echo "$field" | sed -E 's/\.([0-9]+)/[\1]/g' | sed 's/^/./' | sed 's/\.\././g')
  jq -r "$jq_path" "$file"
}

# Write a dotted field path in a JSON file, preserving formatting.
write_json_field() {
  local file="$1" field="$2" value="$3"
  local jq_path
  jq_path=$(echo "$field" | sed -E 's/\.([0-9]+)/[\1]/g' | sed 's/^/./' | sed 's/\.\././g')
  local tmp="${file}.tmp"
  jq "$jq_path = \"$value\"" "$file" > "$tmp" && mv "$tmp" "$file"
}

# Turn a text pattern like "rubypowers.git#v{version}" into a regex that
# captures the version in group 1.
pattern_regex() {
  local pattern="$1"
  local escaped
  escaped=$(printf '%s' "$pattern" | sed -E 's/[][\.^$*+?(){}|\/]/\\&/g')
  printf '%s' "${escaped//\\\{version\\\}/([0-9]+\\.[0-9]+\\.[0-9]+[A-Za-z0-9.-]*)}"
}

# Read the version from a text file using a "{version}" pattern.
# Prints the first match, or "NOT FOUND" when the pattern does not occur.
read_text_pattern() {
  local file="$1" pattern="$2"
  local regex
  regex=$(pattern_regex "$pattern")
  local ver
  ver=$(sed -nE "s/.*${regex}.*/\1/p" "$file" | head -1)
  printf '%s' "${ver:-NOT FOUND}"
}

# Replace every occurrence of a "{version}" pattern in a text file.
write_text_pattern() {
  local file="$1" pattern="$2" value="$3"
  local regex
  regex=$(pattern_regex "$pattern")
  local replacement="${pattern//\{version\}/$value}"
  local tmp="${file}.tmp"
  sed -E "s/${regex}/${replacement//\//\\/}/g" "$file" > "$tmp" && mv "$tmp" "$file"
}

# Read a version from a declared file, JSON field or text pattern.
read_version() {
  local file="$1" kind="$2" spec="$3"
  case "$kind" in
    field) read_json_field "$file" "$spec" ;;
    pattern) read_text_pattern "$file" "$spec" ;;
  esac
}

# Write a version to a declared file, JSON field or text pattern.
write_version() {
  local file="$1" kind="$2" spec="$3" value="$4"
  case "$kind" in
    field) write_json_field "$file" "$spec" "$value" ;;
    pattern) write_text_pattern "$file" "$spec" "$value" ;;
  esac
}

# Read the list of declared files from config.
# Outputs lines of "path<TAB>kind<TAB>spec" where kind is "field" (JSON
# dot-path) or "pattern" (plain text containing "{version}").
declared_files() {
  jq -r '.files[] | if .field then "\(.path)\tfield\t\(.field)" else "\(.path)\tpattern\t\(.pattern)" end' "$CONFIG"
}

# Read the audit exclude patterns from config.
audit_excludes() {
  jq -r '.audit.exclude[]' "$CONFIG" 2>/dev/null
}

# --- commands ---

cmd_check() {
  local has_drift=0
  local versions=()

  echo "Version check:"
  echo ""

  while IFS=$'\t' read -r path kind spec; do
    local fullpath="$REPO_ROOT/$path"
    if [[ ! -f "$fullpath" ]]; then
      printf "  %-55s  MISSING\n" "$path ($spec)"
      has_drift=1
      continue
    fi
    local ver
    ver=$(read_version "$fullpath" "$kind" "$spec")
    printf "  %-55s  %s\n" "$path ($spec)" "$ver"
    versions+=("$ver")
  done < <(declared_files)

  echo ""

  # Check if all versions match
  local unique
  unique=$(printf '%s\n' "${versions[@]}" | sort -u | wc -l | tr -d ' ')
  if [[ "$unique" -gt 1 ]]; then
    echo "DRIFT DETECTED — versions are not in sync:"
    printf '%s\n' "${versions[@]}" | sort | uniq -c | sort -rn | while read -r count ver; do
      echo "  $ver ($count files)"
    done
    has_drift=1
  else
    echo "All declared files are in sync at ${versions[0]}"
  fi

  return $has_drift
}

cmd_audit() {
  # First run check
  cmd_check || true
  echo ""

  # Determine the current version (most common across declared files)
  local current_version
  current_version=$(
    while IFS=$'\t' read -r path kind spec; do
      local fullpath="$REPO_ROOT/$path"
      [[ -f "$fullpath" ]] && read_version "$fullpath" "$kind" "$spec"
    done < <(declared_files) | sort | uniq -c | sort -rn | head -1 | awk '{print $2}'
  )

  if [[ -z "$current_version" ]]; then
    echo "error: could not determine current version" >&2
    return 1
  fi

  echo "Audit: scanning repo for version string '$current_version'..."
  echo ""

  # Build grep exclude args
  local -a exclude_args=()
  while IFS= read -r pattern; do
    exclude_args+=("--exclude=$pattern" "--exclude-dir=$pattern")
  done < <(audit_excludes)

  # Also always exclude binary files and .git
  exclude_args+=("--exclude-dir=.git" "--exclude-dir=node_modules" "--binary-files=without-match")

  # Get list of declared paths for comparison
  local -a declared_paths=()
  while IFS=$'\t' read -r path _kind _spec; do
    declared_paths+=("$path")
  done < <(declared_files)

  # Grep for the version string
  local found_undeclared=0
  while IFS= read -r match; do
    local match_file
    match_file=$(echo "$match" | cut -d: -f1)
    # Make path relative to repo root
    local rel_path="${match_file#$REPO_ROOT/}"

    # Check if this file is in the declared list
    local is_declared=0
    for dp in "${declared_paths[@]}"; do
      if [[ "$rel_path" == "$dp" ]]; then
        is_declared=1
        break
      fi
    done

    if [[ "$is_declared" -eq 0 ]]; then
      if [[ "$found_undeclared" -eq 0 ]]; then
        echo "UNDECLARED files containing '$current_version':"
        found_undeclared=1
      fi
      echo "  $match"
    fi
  done < <(grep -rn "${exclude_args[@]}" -F "$current_version" "$REPO_ROOT" 2>/dev/null || true)

  if [[ "$found_undeclared" -eq 0 ]]; then
    echo "No undeclared files contain the version string. All clear."
  else
    echo ""
    echo "Review the above files — if they should be bumped, add them to .version-bump.json"
    echo "If they should be skipped, add them to the audit.exclude list."
  fi
}

cmd_bump() {
  local new_version="$1"

  # Validate semver-ish format
  if ! echo "$new_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'; then
    echo "error: '$new_version' doesn't look like a version (expected X.Y.Z)" >&2
    exit 1
  fi

  echo "Bumping all declared files to $new_version..."
  echo ""

  while IFS=$'\t' read -r path kind spec; do
    local fullpath="$REPO_ROOT/$path"
    if [[ ! -f "$fullpath" ]]; then
      echo "  SKIP (missing): $path"
      continue
    fi
    local old_ver
    old_ver=$(read_version "$fullpath" "$kind" "$spec")
    write_version "$fullpath" "$kind" "$spec" "$new_version"
    printf "  %-55s  %s -> %s\n" "$path ($spec)" "$old_ver" "$new_version"
  done < <(declared_files)

  echo ""
  echo "Done. Running audit to check for missed files..."
  echo ""
  cmd_audit
}

# --- main ---

case "${1:-}" in
  --check)
    cmd_check
    ;;
  --audit)
    cmd_audit
    ;;
  --help|-h|"")
    echo "Usage: scripts/bump-version.sh <new-version> | --check | --audit"
    echo ""
    echo "  <new-version>  Bump all declared files to the given version"
    echo "  --check        Show current versions, detect drift"
    echo "  --audit        Check + scan repo for undeclared version references"
    exit 0
    ;;
  --*)
    echo "error: unknown flag '$1'" >&2
    exit 1
    ;;
  *)
    cmd_bump "$1"
    ;;
esac
