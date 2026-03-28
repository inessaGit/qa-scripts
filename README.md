# qa-scripts

[![QA Scripts CI](https://github.com/inessaGit/qa-scripts/actions/workflows/scripts.yml/badge.svg)](https://github.com/inessaGit/qa-scripts/actions/workflows/scripts.yml)
[![Python 3.11+](https://img.shields.io/badge/python-3.11%2B-blue.svg)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A QA scripting toolkit in Python and Shell — automating API health checks, test data generation, schema validation, environment setup, and test report management.

---

## Table of Contents

- [Overview](#overview)
- [Tech Stack](#tech-stack)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Python Scripts](#python-scripts)
  - [api\_health\_check.py](#api_health_checkpy)
  - [generate\_test\_data.py](#generate_test_datapy)
  - [validate\_api\_schema.py](#validate_api_schemapy)
  - [test\_api\_health\_check.py](#test_api_health_checkpy)
- [Shell Scripts](#shell-scripts)
  - [run\_tests.sh](#run_testssh)
  - [cleanup\_reports.sh](#cleanup_reportssh)
  - [env\_setup.sh](#env_setupsh)
  - [check\_api\_endpoints.sh](#check_api_endpointssh)
- [CI/CD](#cicd)
- [Example Output](#example-output)

---

## Overview

`qa-scripts` is a collection of reusable automation scripts that complement test frameworks such as Playwright, Pytest, and JUnit. The scripts cover:

- **API health monitoring** — checks multiple endpoints and surfaces status, latency, and pass/fail in a rich terminal table
- **Test data generation** — produces realistic fake user records with Faker, seeded for reproducibility
- **Schema validation** — fetches a live API response and validates it against a JSON Schema file
- **Environment setup** — verifies installed tool versions and initialises `.env` files across sibling repos
- **Report cleanup** — safely removes Allure, Playwright, and coverage directories with a `--dry-run` preview
- **Endpoint smoke checks** — cURL-based health checks against a configurable list of URLs

---

## Tech Stack

| Tool / Library | Version | Purpose |
|---|---|---|
| Python | 3.11+ | Primary scripting language |
| Faker | 24.x | Synthetic test data generation |
| Rich | 13.x | Terminal tables and coloured output |
| requests | 2.31+ | HTTP client for API calls |
| jsonschema | 4.21+ | JSON Schema validation (Draft 7) |
| pytest | 8.1+ | Python test runner |
| python-dotenv | 1.0+ | `.env` file loading |
| Bash | 5.x | Shell automation scripts |
| curl | system | HTTP endpoint probing in shell |
| shellcheck | latest | Shell script linting in CI |
| GitHub Actions | — | CI/CD pipeline |

---

## Project Structure

```
qa-scripts/
├── python/
│   ├── requirements.txt          # Python dependencies
│   ├── api_health_check.py       # Multi-endpoint API health checker
│   ├── generate_test_data.py     # Faker-based test data generator
│   ├── validate_api_schema.py    # JSON Schema validator for API responses
│   └── test_api_health_check.py  # pytest unit tests (mocked HTTP)
├── shell/
│   ├── run_tests.sh              # Test suite runner (npm / mvn)
│   ├── cleanup_reports.sh        # Test report/coverage directory cleaner
│   ├── env_setup.sh              # Tool version checker + .env initialiser
│   └── check_api_endpoints.sh    # cURL-based endpoint smoke checker
├── .github/
│   └── workflows/
│       └── scripts.yml           # GitHub Actions CI workflow
├── .gitignore
└── README.md
```

---

## Prerequisites

| Requirement | Minimum version |
|---|---|
| Python | 3.10 |
| pip | 23.x |
| bash | 4.x (macOS users: `brew install bash`) |
| curl | any recent version |

---

## Installation

Clone the repository and install Python dependencies:

```bash
git clone https://github.com/inessaGit/qa-scripts.git
cd qa-scripts

# Create and activate a virtual environment (recommended)
python3 -m venv venv
source venv/bin/activate   # Windows: venv\Scripts\activate

# Install all Python dependencies
pip install -r python/requirements.txt
```

Make shell scripts executable (if not already):

```bash
chmod +x shell/*.sh
```

---

## Python Scripts

### api\_health\_check.py

Checks the health of multiple public API endpoints (JSONPlaceholder, ReqRes, httpbin) and prints a Rich table with endpoint name, URL, HTTP method, status code, expected status, response time, and PASS/FAIL result. Exits with code `1` if any endpoint fails.

**Flags:**

| Flag | Type | Default | Description |
|---|---|---|---|
| `--timeout` | int | `15` | Request timeout in seconds |
| `--endpoints` | list | built-in | Override with custom URLs (GET, expect 200) |

**Usage:**

```bash
# Run against all built-in endpoints
python python/api_health_check.py

# Custom timeout
python python/api_health_check.py --timeout 5

# Check custom URLs
python python/api_health_check.py --endpoints \
  https://my-api.example.com/health \
  https://other-api.example.com/ping
```

---

### generate\_test\_data.py

Generates N fake user records using Faker and outputs them as a JSON document. Each user includes name, email, phone, company, address, date of birth, role, and other fields. Supports locale selection and a fixed seed for reproducible data.

**Flags:**

| Flag | Short | Default | Description |
|---|---|---|---|
| `--count` | `-n` | `10` | Number of user records to generate |
| `--output-file` | `-o` | stdout | Path to write JSON output |
| `--locale` | `-l` | `en_US` | Faker locale (e.g. `en_GB`, `de_DE`, `fr_FR`) |
| `--seed` | — | none | Fixed random seed for reproducibility |
| `--indent` | — | `2` | JSON indentation (0 for compact) |

**Usage:**

```bash
# Print 10 users to stdout
python python/generate_test_data.py

# Generate 50 users and save to a file
python python/generate_test_data.py --count 50 --output-file test_users.json

# Reproducible British-locale data
python python/generate_test_data.py --count 5 --locale en_GB --seed 42

# Compact JSON for use in another tool
python python/generate_test_data.py --count 100 --indent 0 | jq '.users | length'
```

---

### validate\_api\_schema.py

Fetches a URL and validates the JSON response body against a JSON Schema file (Draft 7). Reports each validation error with a field path and message. Also supports built-in schemas for quick testing without a schema file.

**Flags:**

| Flag | Short | Required | Description |
|---|---|---|---|
| `--url` | `-u` | yes | URL to fetch |
| `--schema` | `-s` | one of | Path to local JSON Schema file |
| `--builtin-schema` | — | one of | Use a built-in schema (`jsonplaceholder_post`, `reqres_user`) |
| `--timeout` | — | no | Request timeout in seconds (default: 15) |
| `--verbose` | `-v` | no | Print the full response body |
| `--header` | — | no | Add HTTP headers, repeatable (`KEY:VALUE`) |

**Usage:**

```bash
# Validate using a schema file
python python/validate_api_schema.py \
  --url https://jsonplaceholder.typicode.com/posts/1 \
  --schema schemas/post.json

# Validate using a built-in schema
python python/validate_api_schema.py \
  --url https://reqres.in/api/users/2 \
  --builtin-schema reqres_user

# Verbose output with a custom header
python python/validate_api_schema.py \
  --url https://api.example.com/user/me \
  --schema schemas/user.json \
  --header "Authorization: Bearer $TOKEN" \
  --verbose
```

---

### test\_api\_health\_check.py

pytest test suite for `api_health_check.py`. All HTTP calls are mocked with `unittest.mock.patch` — no real network requests are made. Tests cover:

- Successful 200 responses
- Unexpected status codes
- Timeout and connection errors
- Exit code 0/1 from `main()`
- Custom `--endpoints` flag
- Timeout value forwarding
- Built-in endpoint list structure

**Usage:**

```bash
# Run all tests
pytest python/test_api_health_check.py -v

# Run a specific test class
pytest python/test_api_health_check.py::TestMain -v

# Run with coverage
pytest python/test_api_health_check.py --cov=python --cov-report=term-missing
```

---

## Shell Scripts

### run\_tests.sh

Runs a test suite using either `npm test` (TypeScript/Playwright) or `mvn test` (Java/JUnit), with configurable environment variables and optional report generation.

**Flags:**

| Flag | Values | Default | Description |
|---|---|---|---|
| `--suite` | `smoke` `regression` `all` | `all` | Test suite to run |
| `--env` | `dev` `ci` | `dev` | Target environment |
| `--type` | `ts` `java` | `ts` | Project type |
| `--report` | — | off | Generate a test report after the run |

**Usage:**

```bash
# Smoke tests in dev with npm
./shell/run_tests.sh --suite smoke --env dev --type ts

# Full regression in CI with Maven + report
./shell/run_tests.sh --suite regression --env ci --type java --report

# All tests, TypeScript, with report
./shell/run_tests.sh --suite all --env dev --type ts --report
```

---

### cleanup\_reports.sh

Finds and removes test artifact directories (`allure-results/`, `allure-report/`, `playwright-report/`, `coverage/`, and others). Use `--dry-run` to preview what would be deleted and how much space would be freed.

**Flags:**

| Flag | Description |
|---|---|
| `--dry-run` | Preview deletions without removing anything |
| `--root DIR` | Root directory to search (default: current directory) |

**Usage:**

```bash
# Preview what would be deleted
./shell/cleanup_reports.sh --dry-run

# Delete report directories in current project
./shell/cleanup_reports.sh

# Clean a specific project directory
./shell/cleanup_reports.sh --root /home/user/projects/my-app

# Dry run on a specific root
./shell/cleanup_reports.sh --dry-run --root ~/projects
```

---

### env\_setup.sh

Checks that all required tools are installed at the correct minimum versions and copies `.env.example` to `.env` in each sibling repository that does not yet have a `.env` file. Exits with code `1` if any required tool is missing or below the minimum version.

**Checks performed:**

| Tool | Minimum version |
|---|---|
| Node.js | 18.x |
| Java | 17 |
| Maven | 3.9 |
| Python | 3.10 |

**Flags:**

| Flag | Description |
|---|---|
| `--repos-root DIR` | Root containing sibling repos (default: parent of script's repo) |
| `--skip-env-copy` | Skip the `.env.example` → `.env` copy step |

**Usage:**

```bash
# Full check including .env copy
./shell/env_setup.sh

# Check only tool versions, skip .env copy
./shell/env_setup.sh --skip-env-copy

# Point at a custom projects root
./shell/env_setup.sh --repos-root ~/projects
```

---

### check\_api\_endpoints.sh

Curls a list of HTTP endpoints, checks the actual status code against the expected value, and prints a coloured PASS/FAIL summary for each. Defaults to a built-in set of public API endpoints. Supports a custom endpoints file.

**Flags:**

| Flag | Default | Description |
|---|---|---|
| `--timeout N` | `15` | Per-request timeout in seconds |
| `--endpoints-file F` | built-in | File with endpoints (one per line: `METHOD URL [STATUS]`) |
| `--base-url URL` | — | Prepend base URL to relative paths in endpoints file |
| `--fail-fast` | off | Stop checking after the first failure |

**Usage:**

```bash
# Check all built-in endpoints
./shell/check_api_endpoints.sh

# Custom timeout
./shell/check_api_endpoints.sh --timeout 5

# Load endpoints from a file
./shell/check_api_endpoints.sh --endpoints-file smoke_endpoints.txt

# Use a base URL for relative paths
./shell/check_api_endpoints.sh \
  --endpoints-file endpoints.txt \
  --base-url https://staging.example.com

# Stop on first failure
./shell/check_api_endpoints.sh --fail-fast
```

**Endpoints file format:**

```text
# Health checks
GET  /health           200
GET  /api/version      200
POST /api/login        200
GET  /api/users        200

# Full URLs also work
GET  https://external.example.com/ping   200
```

---

## CI/CD

The GitHub Actions workflow at `.github/workflows/scripts.yml` runs on every push and pull request to `main`, `master`, and `develop`.

**Jobs:**

| Job | What it does |
|---|---|
| `python-tests` | Installs dependencies and runs pytest on Python 3.11 and 3.12 |
| `lint-python` | Runs flake8 across all Python scripts |
| `validate-shell-scripts` | Runs shellcheck on all shell scripts |
| `dry-run-python-scripts` | Smoke-tests `generate_test_data.py` and `validate_api_schema.py` end-to-end |

Coverage reports are uploaded as build artifacts and retained for 7 days.

To run the same checks locally:

```bash
# Python tests
pytest python/test_api_health_check.py -v

# Lint
flake8 python/ --max-line-length=120

# Shell lint (requires shellcheck)
shellcheck shell/*.sh
```

---

## Example Output

```
Running health checks against 7 endpoint(s) with timeout=15s

  Checking JSONPlaceholder — GET post … done
  Checking JSONPlaceholder — GET users … done
  Checking ReqRes — GET users … done
  Checking ReqRes — GET single user … done
  Checking httpbin — GET /get … done
  Checking httpbin — GET /status/200 … done
  Checking httpbin — GET /json … done

╭─────────────────────────────────────────────────────────────────────────────────────────────────╮
│                                    API Health Check Results                                     │
├──────────────────────────────────┬─────────────────────────────────────┬────────┬────────┬──────┤
│ Endpoint                         │ URL                                 │ Method │ Status │ ...  │
├──────────────────────────────────┼─────────────────────────────────────┼────────┼────────┼──────┤
│ JSONPlaceholder — GET post       │ https://jsonplaceholder.typicode... │  GET   │  200   │ PASS │
│ JSONPlaceholder — GET users      │ https://jsonplaceholder.typicode... │  GET   │  200   │ PASS │
│ ReqRes — GET users               │ https://reqres.in/api/users?page=1  │  GET   │  200   │ PASS │
│ ReqRes — GET single user         │ https://reqres.in/api/users/2       │  GET   │  200   │ PASS │
│ httpbin — GET /get               │ https://httpbin.org/get             │  GET   │  200   │ PASS │
│ httpbin — GET /status/200        │ https://httpbin.org/status/200      │  GET   │  200   │ PASS │
│ httpbin — GET /json              │ https://httpbin.org/json            │  GET   │  200   │ PASS │
╰──────────────────────────────────┴─────────────────────────────────────┴────────┴────────┴──────╯

Summary: 7 passed / 0 failed / 7 total

All endpoints healthy.
```
