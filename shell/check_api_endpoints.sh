#!/usr/bin/env bash
# check_api_endpoints.sh — Curl a list of HTTP endpoints and report pass/fail.
#
# Usage:
#   ./check_api_endpoints.sh
#   ./check_api_endpoints.sh --timeout 10
#   ./check_api_endpoints.sh --endpoints-file my_endpoints.txt
#   ./check_api_endpoints.sh --base-url https://staging.example.com
#   ./check_api_endpoints.sh --fail-fast
#   ./check_api_endpoints.sh --help
#
# Endpoint file format (one per line):
#   METHOD URL [EXPECTED_STATUS]
#   GET    https://api.example.com/health   200
#   POST   https://api.example.com/login    200
#
# Lines starting with # are treated as comments.

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
pass()    { echo -e "${GREEN}[PASS]${RESET}  $*"; }
fail()    { echo -e "${RED}[FAIL]${RESET}  $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
header()  { echo -e "\n${BOLD}${CYAN}=== $* ===${RESET}\n"; }

# ---------------------------------------------------------------------------
# Built-in default endpoints
# Array format: "METHOD URL EXPECTED_STATUS DESCRIPTION"
# ---------------------------------------------------------------------------
DEFAULT_ENDPOINTS=(
  "GET https://jsonplaceholder.typicode.com/posts/1 200 JSONPlaceholder - GET post"
  "GET https://jsonplaceholder.typicode.com/users 200 JSONPlaceholder - GET users"
  "GET https://reqres.in/api/users?page=1 200 ReqRes - GET users list"
  "GET https://reqres.in/api/users/2 200 ReqRes - GET single user"
  "GET https://httpbin.org/get 200 httpbin - GET /get"
  "GET https://httpbin.org/json 200 httpbin - GET /json"
  "GET https://httpbin.org/status/200 200 httpbin - GET /status/200"
  "GET https://httpbin.org/status/404 404 httpbin - GET /status/404"
)

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
TIMEOUT=15
FAIL_FAST=false
ENDPOINTS_FILE=""
BASE_URL=""
TOTAL=0
PASSED=0
FAILED=0
START_TIME=$(date +%s)

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF

${BOLD}check_api_endpoints.sh${RESET} — HTTP endpoint health checker.

${BOLD}Usage:${RESET}
  $(basename "$0") [OPTIONS]

${BOLD}Options:${RESET}
  --timeout N          Request timeout in seconds        (default: 15)
  --endpoints-file F   File with endpoints to check      (default: built-in list)
  --base-url URL       Prepend base URL to relative paths
  --fail-fast          Stop on first failure
  --help               Show this help message

${BOLD}Endpoints file format:${RESET}
  # Comment line
  GET  /health          200
  POST /api/login       200
  GET  https://full.url 200   Optional description

${BOLD}Examples:${RESET}
  $(basename "$0") --timeout 5
  $(basename "$0") --endpoints-file endpoints.txt --base-url https://dev.example.com
  $(basename "$0") --fail-fast --timeout 10

EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --timeout)
      TIMEOUT="${2:-15}"
      shift 2
      ;;
    --endpoints-file)
      ENDPOINTS_FILE="${2:-}"
      if [[ -z "$ENDPOINTS_FILE" ]]; then
        echo -e "${RED}[ERROR]${RESET} --endpoints-file requires a path argument." >&2
        exit 1
      fi
      shift 2
      ;;
    --base-url)
      BASE_URL="${2:-}"
      shift 2
      ;;
    --fail-fast)
      FAIL_FAST=true
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
# Prerequisite check
# ---------------------------------------------------------------------------
if ! command -v curl &>/dev/null; then
  echo -e "${RED}[ERROR]${RESET} curl is required but not found. Please install curl." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Build endpoint list
# ---------------------------------------------------------------------------
declare -a ENDPOINT_LIST=()

if [[ -n "$ENDPOINTS_FILE" ]]; then
  if [[ ! -f "$ENDPOINTS_FILE" ]]; then
    echo -e "${RED}[ERROR]${RESET} Endpoints file not found: '$ENDPOINTS_FILE'" >&2
    exit 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip blank lines and comments
    [[ -z "${line// }" || "$line" =~ ^[[:space:]]*# ]] && continue
    ENDPOINT_LIST+=("$line")
  done < "$ENDPOINTS_FILE"

  info "Loaded ${#ENDPOINT_LIST[@]} endpoint(s) from '$ENDPOINTS_FILE'"
else
  ENDPOINT_LIST=("${DEFAULT_ENDPOINTS[@]}")
  info "Using ${#ENDPOINT_LIST[@]} built-in endpoint(s)"
fi

if [[ ${#ENDPOINT_LIST[@]} -eq 0 ]]; then
  warn "No endpoints to check. Exiting."
  exit 0
fi

# ---------------------------------------------------------------------------
# Check a single endpoint
# Returns 0 on pass, 1 on fail
# ---------------------------------------------------------------------------
check_endpoint() {
  local method="$1"
  local url="$2"
  local expected_status="${3:-200}"
  local description="${4:-$url}"

  # Prepend base URL to relative paths
  if [[ -n "$BASE_URL" && "$url" != http* ]]; then
    url="${BASE_URL%/}/${url#/}"
  fi

  local http_status elapsed

  # Measure response time and capture HTTP status code
  local start_ns
  if command -v gdate &>/dev/null; then
    start_ns=$(gdate +%s%N 2>/dev/null || date +%s)
  else
    start_ns=$(date +%s)
  fi

  http_status=$(
    curl \
      --silent \
      --output /dev/null \
      --write-out "%{http_code}" \
      --request "$method" \
      --max-time "$TIMEOUT" \
      --location \
      "$url" 2>/dev/null
  ) || http_status="000"

  local end_ns
  if command -v gdate &>/dev/null; then
    end_ns=$(gdate +%s%N 2>/dev/null || date +%s)
    elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
  else
    end_ns=$(date +%s)
    elapsed_ms=$(( (end_ns - start_ns) * 1000 ))
  fi

  local result_line
  result_line=$(printf "%-10s %-8s %s  ->  status=%-3s  expected=%-3s  time=%dms" \
    "$method" "" "$description" "$http_status" "$expected_status" "$elapsed_ms")

  (( TOTAL++ )) || true

  if [[ "$http_status" == "$expected_status" ]]; then
    pass "$result_line"
    (( PASSED++ )) || true
    return 0
  else
    fail "$result_line"
    (( FAILED++ )) || true
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  header "API Endpoint Health Check"
  info "Timeout:   ${TIMEOUT}s"
  info "Fail-fast: $FAIL_FAST"
  [[ -n "$BASE_URL" ]] && info "Base URL:  $BASE_URL"
  echo ""

  for entry in "${ENDPOINT_LIST[@]}"; do
    # Parse: METHOD URL [EXPECTED_STATUS] [DESCRIPTION...]
    read -r method url expected_status description <<< "$entry" || true
    method="${method:-GET}"
    url="${url:-}"
    expected_status="${expected_status:-200}"
    description="${description:-$url}"

    [[ -z "$url" ]] && continue

    if ! check_endpoint "$method" "$url" "$expected_status" "$description"; then
      if [[ "$FAIL_FAST" == "true" ]]; then
        echo ""
        warn "Fail-fast mode: stopping after first failure."
        break
      fi
    fi
  done

  # ---------------------------------------------------------------------------
  # Summary
  # ---------------------------------------------------------------------------
  local end_time elapsed
  end_time=$(date +%s)
  elapsed=$(( end_time - START_TIME ))

  header "Summary"

  printf "  ${BOLD}%-15s${RESET} %d\n" "Total:"  "$TOTAL"
  printf "  ${GREEN}${BOLD}%-15s${RESET}${GREEN} %d${RESET}\n" "Passed:"  "$PASSED"
  printf "  ${RED}${BOLD}%-15s${RESET}${RED} %d${RESET}\n"   "Failed:"  "$FAILED"
  printf "  ${BOLD}%-15s${RESET} %ds\n" "Duration:" "$elapsed"
  echo ""

  if (( FAILED > 0 )); then
    echo -e "${RED}${BOLD}RESULT: FAILED${RESET} — $FAILED endpoint(s) did not return expected status."
    echo ""
    exit 1
  else
    echo -e "${GREEN}${BOLD}RESULT: PASSED${RESET} — All $PASSED endpoint(s) returned expected status."
    echo ""
  fi
}

main "$@"
