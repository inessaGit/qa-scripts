#!/usr/bin/env bash
# env_setup.sh — Verify required tools are installed and copy .env files.
#
# Checks:
#   • Node.js >= 18
#   • Java   >= 17
#   • Maven  >= 3.9
#   • Python >= 3.10
#
# Also copies .env.example -> .env in each sibling repository directory
# (direct children of the parent of this script's repo root).
#
# Usage:
#   ./env_setup.sh
#   ./env_setup.sh --repos-root /path/to/projects
#   ./env_setup.sh --skip-env-copy
#   ./env_setup.sh --help

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
success() { echo -e "${GREEN}[ ✓ ]${RESET}  $*"; }
fail_msg(){ echo -e "${RED}[ ✗ ]${RESET}  $*" >&2; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}\n"; }

# ---------------------------------------------------------------------------
# Script location — used to find sibling repos
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Repo root is two levels up from shell/ (qa-scripts/shell/ -> qa-scripts/ -> parent)
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
REPOS_ROOT="$REPO_ROOT"
SKIP_ENV_COPY=false
ERRORS=0

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF

${BOLD}env_setup.sh${RESET} — Verify tool versions and initialise .env files.

${BOLD}Usage:${RESET}
  $(basename "$0") [OPTIONS]

${BOLD}Options:${RESET}
  --repos-root DIR   Root directory containing sibling repos (default: $REPO_ROOT)
  --skip-env-copy    Skip .env.example → .env copy step
  --help             Show this help message

${BOLD}Required tool versions:${RESET}
  Node.js  >= 18
  Java     >= 17
  Maven    >= 3.9
  Python   >= 3.10

EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repos-root)
      REPOS_ROOT="${2:-}"
      if [[ -z "$REPOS_ROOT" ]]; then
        echo -e "${RED}[ERROR]${RESET} --repos-root requires a directory path." >&2
        exit 1
      fi
      shift 2
      ;;
    --skip-env-copy)
      SKIP_ENV_COPY=true
      shift
      ;;
    --help|-h)
      usage
      ;;
    *)
      echo -e "${RED}[ERROR]${RESET} Unknown argument: '$1'" >&2
      usage
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Version comparison helpers
# ---------------------------------------------------------------------------

# Returns the numeric portion of a version string, e.g. "3.11.2" -> "3 11 2"
split_version() { echo "$1" | tr '.' ' '; }

# version_gte VERSION MIN_MAJOR MIN_MINOR
# Returns 0 (true) if VERSION major.minor >= MIN_MAJOR.MIN_MINOR
version_gte() {
  local version="$1" min_major="$2" min_minor="${3:-0}"
  read -r v_major v_minor _ <<< "$(split_version "$version")"
  v_major="${v_major:-0}"
  v_minor="${v_minor:-0}"

  if (( v_major > min_major )); then return 0; fi
  if (( v_major == min_major && v_minor >= min_minor )); then return 0; fi
  return 1
}

# ---------------------------------------------------------------------------
# Individual tool checks
# ---------------------------------------------------------------------------

check_node() {
  local min_major=18
  if ! command -v node &>/dev/null; then
    fail_msg "Node.js not found. Install Node.js >= ${min_major}: https://nodejs.org"
    (( ERRORS++ )) || true
    return
  fi

  local version
  version=$(node --version | sed 's/^v//')
  if version_gte "$version" "$min_major" 0; then
    success "Node.js $version  (required >= ${min_major}.x)"
  else
    fail_msg "Node.js $version found but >= ${min_major}.x required."
    (( ERRORS++ )) || true
  fi
}

check_java() {
  local min_major=17
  if ! command -v java &>/dev/null; then
    fail_msg "Java not found. Install JDK >= ${min_major}: https://adoptium.net"
    (( ERRORS++ )) || true
    return
  fi

  # java -version prints to stderr
  local version_line
  version_line=$(java -version 2>&1 | head -1)
  # Handles: openjdk version "17.0.10" and java version "11.0.2"
  local version
  version=$(echo "$version_line" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)
  local major
  major=$(echo "$version" | cut -d. -f1)

  # Java 9+ uses single-digit major, older used 1.X format
  if [[ "$major" == "1" ]]; then
    major=$(echo "$version" | cut -d. -f2)
  fi

  if (( major >= min_major )); then
    success "Java $version  (required >= ${min_major})"
  else
    fail_msg "Java $version found but >= ${min_major} required."
    (( ERRORS++ )) || true
  fi
}

check_maven() {
  local min_major=3 min_minor=9
  if ! command -v mvn &>/dev/null; then
    fail_msg "Maven not found. Install Maven >= ${min_major}.${min_minor}: https://maven.apache.org"
    (( ERRORS++ )) || true
    return
  fi

  local version
  version=$(mvn --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)

  if version_gte "$version" "$min_major" "$min_minor"; then
    success "Maven $version  (required >= ${min_major}.${min_minor})"
  else
    fail_msg "Maven $version found but >= ${min_major}.${min_minor} required."
    (( ERRORS++ )) || true
  fi
}

check_python() {
  local min_major=3 min_minor=10
  local python_cmd=""

  # Prefer python3 over python
  if command -v python3 &>/dev/null; then
    python_cmd="python3"
  elif command -v python &>/dev/null; then
    python_cmd="python"
  fi

  if [[ -z "$python_cmd" ]]; then
    fail_msg "Python not found. Install Python >= ${min_major}.${min_minor}: https://python.org"
    (( ERRORS++ )) || true
    return
  fi

  local version
  version=$("$python_cmd" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)

  if version_gte "$version" "$min_major" "$min_minor"; then
    success "Python $version  (required >= ${min_major}.${min_minor})  [$python_cmd]"
  else
    fail_msg "Python $version found but >= ${min_major}.${min_minor} required."
    (( ERRORS++ )) || true
  fi
}

# ---------------------------------------------------------------------------
# .env copy
# ---------------------------------------------------------------------------
copy_env_files() {
  header ".env File Initialisation"
  info "Scanning sibling repos under: $REPOS_ROOT"
  echo ""

  local copied=0 skipped=0 missing=0

  # Iterate over direct subdirectories of REPOS_ROOT
  while IFS= read -r -d '' repo_dir; do
    [[ -d "$repo_dir" ]] || continue

    local repo_name
    repo_name=$(basename "$repo_dir")

    local example="$repo_dir/.env.example"
    local target="$repo_dir/.env"

    if [[ ! -f "$example" ]]; then
      info "  $repo_name  — no .env.example, skipping"
      (( missing++ )) || true
      continue
    fi

    if [[ -f "$target" ]]; then
      warn "  $repo_name  — .env already exists, skipping"
      (( skipped++ )) || true
    else
      cp "$example" "$target"
      success "  $repo_name  — copied .env.example → .env"
      (( copied++ )) || true
    fi
  done < <(find "$REPOS_ROOT" -maxdepth 1 -mindepth 1 -type d -print0 | sort -z)

  echo ""
  info "Copied:  $copied"
  info "Skipped: $skipped  (already existed)"
  info "No .env.example: $missing"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  header "Environment Setup Check"
  info "Running on: $(uname -s) $(uname -m)"
  info "Date:       $(date '+%Y-%m-%d %H:%M:%S')"
  echo ""

  header "Tool Version Checks"

  check_node
  check_java
  check_maven
  check_python

  echo ""

  if [[ "$SKIP_ENV_COPY" == "false" ]]; then
    copy_env_files
  else
    info "Skipping .env copy (--skip-env-copy set)."
  fi

  header "Result"

  if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}${BOLD}$ERRORS required tool(s) are missing or out of date.${RESET}"
    echo -e "${RED}Please install the missing tools before continuing.${RESET}"
    echo ""
    exit 1
  else
    echo -e "${GREEN}${BOLD}All required tools are present and meet version requirements.${RESET}"
    echo ""
  fi
}

main "$@"
