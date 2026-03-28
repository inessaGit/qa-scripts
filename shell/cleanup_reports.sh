#!/usr/bin/env bash
# cleanup_reports.sh — Find and remove test report/coverage directories.
#
# Usage:
#   ./cleanup_reports.sh
#   ./cleanup_reports.sh --dry-run
#   ./cleanup_reports.sh --root /path/to/project
#   ./cleanup_reports.sh --dry-run --root /path/to/project
#
# Options:
#   --dry-run   Preview what would be deleted without removing anything
#   --root DIR  Root directory to search (default: current directory)
#   --help      Show this help message

set -euo pipefail

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${BLUE}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}\n"; }

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
DRY_RUN=false
SEARCH_ROOT="."

# Report/coverage directory patterns to clean up
TARGET_DIRS=(
  "allure-results"
  "allure-report"
  "playwright-report"
  "coverage"
  "test-results"
  "html-report"
  ".nyc_output"
  "target/surefire-reports"
  "target/failsafe-reports"
)

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF

${BOLD}cleanup_reports.sh${RESET} — Remove test report and coverage directories.

${BOLD}Usage:${RESET}
  $(basename "$0") [OPTIONS]

${BOLD}Options:${RESET}
  --dry-run        Preview deletions without removing anything
  --root DIR       Root directory to search (default: current directory)
  --help           Show this help message

${BOLD}Directories targeted:${RESET}
$(printf '  • %s\n' "${TARGET_DIRS[@]}")

${BOLD}Examples:${RESET}
  $(basename "$0") --dry-run
  $(basename "$0") --root /home/user/projects/my-app
  $(basename "$0") --dry-run --root /home/user/projects

EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --root)
      SEARCH_ROOT="${2:-}"
      if [[ -z "$SEARCH_ROOT" ]]; then
        error "--root requires a directory argument."
        exit 1
      fi
      shift 2
      ;;
    --help|-h)
      usage
      ;;
    *)
      error "Unknown argument: '$1'"
      usage
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Validate root directory
# ---------------------------------------------------------------------------
if [[ ! -d "$SEARCH_ROOT" ]]; then
  error "Search root directory not found: '$SEARCH_ROOT'"
  exit 1
fi

SEARCH_ROOT=$(realpath "$SEARCH_ROOT")

# ---------------------------------------------------------------------------
# Human-readable byte size
# ---------------------------------------------------------------------------
human_size() {
  local bytes="$1"
  if   (( bytes >= 1073741824 )); then printf "%.2f GB" "$(echo "scale=2; $bytes/1073741824" | bc)"
  elif (( bytes >= 1048576    )); then printf "%.2f MB" "$(echo "scale=2; $bytes/1048576"    | bc)"
  elif (( bytes >= 1024       )); then printf "%.2f KB" "$(echo "scale=2; $bytes/1024"       | bc)"
  else printf "%d B" "$bytes"
  fi
}

# ---------------------------------------------------------------------------
# Get directory size in bytes (cross-platform: macOS & Linux)
# ---------------------------------------------------------------------------
dir_size_bytes() {
  local dir="$1"
  if command -v du &>/dev/null; then
    # -s = summary, -k = kilobytes (POSIX); multiply by 1024 for bytes
    local kb
    kb=$(du -sk "$dir" 2>/dev/null | awk '{print $1}')
    echo $(( kb * 1024 ))
  else
    echo 0
  fi
}

# ---------------------------------------------------------------------------
# Main logic
# ---------------------------------------------------------------------------
header "QA Report Cleanup"

if [[ "$DRY_RUN" == "true" ]]; then
  warn "DRY RUN MODE — no files will be deleted."
fi

info "Search root: $SEARCH_ROOT"
echo ""

found_dirs=()
found_sizes=()
total_bytes=0

# Walk each target pattern and find matching directories
for pattern in "${TARGET_DIRS[@]}"; do
  while IFS= read -r -d '' dir; do
    if [[ -d "$dir" ]]; then
      size=$(dir_size_bytes "$dir")
      found_dirs+=("$dir")
      found_sizes+=("$size")
      total_bytes=$(( total_bytes + size ))
    fi
  done < <(find "$SEARCH_ROOT" -type d -name "$(basename "$pattern")" -print0 2>/dev/null)
done

# ---------------------------------------------------------------------------
# Report findings
# ---------------------------------------------------------------------------
if [[ ${#found_dirs[@]} -eq 0 ]]; then
  success "No report/coverage directories found. Nothing to clean."
  exit 0
fi

info "Found ${#found_dirs[@]} director(ies) to clean:"
echo ""

for i in "${!found_dirs[@]}"; do
  size_str=$(human_size "${found_sizes[$i]}")
  if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "  ${YELLOW}[DRY RUN]${RESET} Would delete: ${found_dirs[$i]} ${CYAN}(${size_str})${RESET}"
  else
    echo -e "  ${RED}[-]${RESET} ${found_dirs[$i]} ${CYAN}(${size_str})${RESET}"
  fi
done

echo ""
total_human=$(human_size "$total_bytes")

# ---------------------------------------------------------------------------
# Deletion
# ---------------------------------------------------------------------------
deleted_count=0
failed_count=0

if [[ "$DRY_RUN" == "false" ]]; then
  header "Deleting Directories"

  for dir in "${found_dirs[@]}"; do
    if rm -rf "$dir" 2>/dev/null; then
      success "Deleted: $dir"
      (( deleted_count++ )) || true
    else
      error "Failed to delete: $dir"
      (( failed_count++ )) || true
    fi
  done
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
header "Summary"

if [[ "$DRY_RUN" == "true" ]]; then
  info "Mode:              DRY RUN (no changes made)"
  info "Directories found: ${#found_dirs[@]}"
  info "Space that would be freed: $total_human"
  echo ""
  warn "Re-run without --dry-run to perform the actual cleanup."
else
  info "Directories deleted: $deleted_count"
  if [[ $failed_count -gt 0 ]]; then
    warn "Directories failed:  $failed_count"
  fi
  info "Space freed:         $total_human"

  if [[ $failed_count -gt 0 ]]; then
    echo ""
    error "$failed_count deletion(s) failed. Check permissions."
    exit 1
  else
    echo ""
    success "Cleanup complete."
  fi
fi

echo ""
