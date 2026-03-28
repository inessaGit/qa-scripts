#!/usr/bin/env bash
# run_tests.sh — Run a test suite with configurable environment and type.
#
# Usage:
#   ./run_tests.sh --suite smoke --env dev --type ts
#   ./run_tests.sh --suite regression --env ci --type java --report
#   ./run_tests.sh --suite all --env dev --type ts --report
#   ./run_tests.sh --help
#
# Options:
#   --suite    smoke | regression | all       (default: all)
#   --env      dev | ci                       (default: dev)
#   --type     ts | java                      (default: ts)
#   --report   Generate test report after run (optional flag)
#   --help     Show this help message

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
SUITE="all"
ENV="dev"
TYPE="ts"
REPORT=false
START_TIME=$(date +%s)

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
  cat <<EOF

${BOLD}run_tests.sh${RESET} — Execute QA test suites.

${BOLD}Usage:${RESET}
  $(basename "$0") [OPTIONS]

${BOLD}Options:${RESET}
  --suite    smoke | regression | all   Test suite to run     (default: all)
  --env      dev | ci                   Target environment     (default: dev)
  --type     ts | java                  Project type           (default: ts)
  --report                              Generate report after run
  --help                                Show this help message

${BOLD}Examples:${RESET}
  $(basename "$0") --suite smoke --env dev --type ts
  $(basename "$0") --suite regression --env ci --type java --report
  $(basename "$0") --suite all --env dev --type ts --report

EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --suite)
      SUITE="${2:-}"
      shift 2
      ;;
    --env)
      ENV="${2:-}"
      shift 2
      ;;
    --type)
      TYPE="${2:-}"
      shift 2
      ;;
    --report)
      REPORT=true
      shift
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
# Validation
# ---------------------------------------------------------------------------
validate_args() {
  local valid=true

  case "$SUITE" in
    smoke|regression|all) ;;
    *)
      error "Invalid --suite value: '$SUITE'. Must be smoke, regression, or all."
      valid=false
      ;;
  esac

  case "$ENV" in
    dev|ci) ;;
    *)
      error "Invalid --env value: '$ENV'. Must be dev or ci."
      valid=false
      ;;
  esac

  case "$TYPE" in
    ts|java) ;;
    *)
      error "Invalid --type value: '$TYPE'. Must be ts or java."
      valid=false
      ;;
  esac

  if [[ "$valid" == "false" ]]; then
    echo ""
    usage
  fi
}

validate_args

# ---------------------------------------------------------------------------
# Export environment variables
# ---------------------------------------------------------------------------
export_env_vars() {
  header "Environment Configuration"

  export TEST_ENV="$ENV"
  export TEST_SUITE="$SUITE"
  export TEST_TYPE="$TYPE"

  case "$ENV" in
    dev)
      export BASE_URL="${BASE_URL:-http://localhost:3000}"
      export API_TIMEOUT="${API_TIMEOUT:-10000}"
      export LOG_LEVEL="${LOG_LEVEL:-debug}"
      ;;
    ci)
      export BASE_URL="${BASE_URL:-http://app:3000}"
      export API_TIMEOUT="${API_TIMEOUT:-30000}"
      export LOG_LEVEL="${LOG_LEVEL:-info}"
      ;;
  esac

  info "TEST_ENV     = $TEST_ENV"
  info "TEST_SUITE   = $TEST_SUITE"
  info "TEST_TYPE    = $TEST_TYPE"
  info "BASE_URL     = $BASE_URL"
  info "API_TIMEOUT  = $API_TIMEOUT"
  info "LOG_LEVEL    = $LOG_LEVEL"
}

# ---------------------------------------------------------------------------
# Build tag/grep filter for suite
# ---------------------------------------------------------------------------
get_suite_filter() {
  case "$SUITE" in
    smoke)      echo "@smoke" ;;
    regression) echo "@regression" ;;
    all)        echo "" ;;
  esac
}

# ---------------------------------------------------------------------------
# TypeScript / npm test runner
# ---------------------------------------------------------------------------
run_ts_tests() {
  header "Running TypeScript Tests (npm)"

  if ! command -v npm &>/dev/null; then
    error "npm not found. Install Node.js >= 18 to run TypeScript tests."
    exit 1
  fi

  local npm_version
  npm_version=$(npm --version)
  info "npm version: $npm_version"

  local filter
  filter=$(get_suite_filter)

  local npm_args=("run" "test")

  if [[ -n "$filter" ]]; then
    npm_args+=("--" "--grep" "$filter")
    info "Suite filter: $filter"
  else
    info "Running ALL tests"
  fi

  if [[ "$ENV" == "ci" ]]; then
    npm_args+=("--" "--reporter" "dot")
  fi

  info "Command: npm ${npm_args[*]}"
  echo ""

  if npm "${npm_args[@]}"; then
    success "TypeScript tests completed successfully."
  else
    error "TypeScript tests FAILED."
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Java / Maven test runner
# ---------------------------------------------------------------------------
run_java_tests() {
  header "Running Java Tests (Maven)"

  if ! command -v mvn &>/dev/null; then
    error "mvn not found. Install Maven >= 3.9 to run Java tests."
    exit 1
  fi

  local mvn_version
  mvn_version=$(mvn --version | head -1)
  info "Maven version: $mvn_version"

  local filter
  filter=$(get_suite_filter)

  local mvn_args=("test")

  case "$SUITE" in
    smoke)
      mvn_args+=("-Dgroups=smoke")
      info "Suite filter: groups=smoke"
      ;;
    regression)
      mvn_args+=("-Dgroups=regression")
      info "Suite filter: groups=regression"
      ;;
    all)
      info "Running ALL tests"
      ;;
  esac

  if [[ "$ENV" == "ci" ]]; then
    mvn_args+=("-Dsurefire.useFile=false" "-B")
  fi

  info "Command: mvn ${mvn_args[*]}"
  echo ""

  if mvn "${mvn_args[@]}"; then
    success "Java tests completed successfully."
  else
    error "Java tests FAILED."
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# Report generation
# ---------------------------------------------------------------------------
generate_report() {
  header "Generating Test Report"

  case "$TYPE" in
    ts)
      if command -v npx &>/dev/null && npx playwright --version &>/dev/null 2>&1; then
        info "Generating Playwright HTML report…"
        npx playwright show-report --host=0.0.0.0 &
        success "Playwright report server started."
      elif [[ -d "allure-results" ]]; then
        info "Generating Allure report from allure-results/…"
        if command -v allure &>/dev/null; then
          allure generate allure-results --clean -o allure-report
          success "Allure report generated in allure-report/"
        else
          warn "allure CLI not found. Skipping Allure report generation."
        fi
      else
        warn "No known report artifacts found (playwright-report/, allure-results/)."
      fi
      ;;
    java)
      if [[ -d "target/surefire-reports" ]]; then
        info "Surefire reports available at: target/surefire-reports/"
      fi
      if [[ -d "allure-results" ]] && command -v allure &>/dev/null; then
        info "Generating Allure report…"
        allure generate allure-results --clean -o allure-report
        success "Allure report generated in allure-report/"
      else
        warn "allure CLI not found or allure-results/ missing. Skipping."
      fi
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
print_summary() {
  local end_time elapsed
  end_time=$(date +%s)
  elapsed=$((end_time - START_TIME))

  header "Run Summary"
  info "Suite:       $SUITE"
  info "Environment: $ENV"
  info "Type:        $TYPE"
  info "Report:      $REPORT"
  info "Duration:    ${elapsed}s"
  success "Test run complete."
  echo ""
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  header "QA Test Runner"
  info "Started at: $(date '+%Y-%m-%d %H:%M:%S')"

  export_env_vars

  case "$TYPE" in
    ts)   run_ts_tests ;;
    java) run_java_tests ;;
  esac

  if [[ "$REPORT" == "true" ]]; then
    generate_report
  fi

  print_summary
}

main "$@"
