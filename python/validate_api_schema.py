#!/usr/bin/env python3
"""
validate_api_schema.py — Fetch a URL and validate the JSON response against a schema file.

Usage:
    python validate_api_schema.py --url https://jsonplaceholder.typicode.com/posts/1 \
                                   --schema schemas/post.json
    python validate_api_schema.py --url https://reqres.in/api/users/2 \
                                   --schema schemas/reqres_user.json \
                                   --timeout 10
    python validate_api_schema.py --url URL --schema SCHEMA --verbose
"""

import argparse
import json
import sys
from pathlib import Path

import requests
import jsonschema
from jsonschema import validate, Draft7Validator, SchemaError


# ---------------------------------------------------------------------------
# Built-in example schemas used when --schema is not provided
# ---------------------------------------------------------------------------

EXAMPLE_SCHEMAS = {
    "jsonplaceholder_post": {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "title": "JSONPlaceholder Post",
        "type": "object",
        "required": ["userId", "id", "title", "body"],
        "properties": {
            "userId": {"type": "integer"},
            "id": {"type": "integer"},
            "title": {"type": "string", "minLength": 1},
            "body": {"type": "string", "minLength": 1},
        },
        "additionalProperties": False,
    },
    "reqres_user": {
        "$schema": "http://json-schema.org/draft-07/schema#",
        "title": "ReqRes Single User Response",
        "type": "object",
        "required": ["data", "support"],
        "properties": {
            "data": {
                "type": "object",
                "required": ["id", "email", "first_name", "last_name", "avatar"],
                "properties": {
                    "id": {"type": "integer"},
                    "email": {"type": "string", "format": "email"},
                    "first_name": {"type": "string"},
                    "last_name": {"type": "string"},
                    "avatar": {"type": "string", "format": "uri"},
                },
            },
            "support": {
                "type": "object",
                "required": ["url", "text"],
                "properties": {
                    "url": {"type": "string"},
                    "text": {"type": "string"},
                },
            },
        },
    },
}


def load_schema(schema_path: str) -> dict:
    """Load and parse a JSON schema from disk."""
    path = Path(schema_path)
    if not path.exists():
        raise FileNotFoundError(f"Schema file not found: {path.resolve()}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise ValueError(f"Invalid JSON in schema file '{path}': {exc}") from exc


def fetch_response(url: str, timeout: int, headers: dict | None = None) -> tuple[dict | list, int]:
    """Fetch URL and return (parsed_body, status_code)."""
    resp = requests.get(url, timeout=timeout, headers=headers or {})
    resp.raise_for_status()
    return resp.json(), resp.status_code


def validate_against_schema(data: dict | list, schema: dict) -> list[str]:
    """
    Validate data against schema using Draft7Validator.
    Returns a list of error messages (empty list means valid).
    """
    validator = Draft7Validator(schema)
    errors = sorted(validator.iter_errors(data), key=lambda e: list(e.path))
    return [
        f"  [{'.'.join(str(p) for p in e.path) or 'root'}] {e.message}"
        for e in errors
    ]


def parse_args(argv=None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Fetch a URL and validate the JSON response against a JSON Schema.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--url",
        "-u",
        required=True,
        metavar="URL",
        help="URL to fetch and validate",
    )
    parser.add_argument(
        "--schema",
        "-s",
        default=None,
        metavar="FILE",
        help="Path to JSON schema file. If omitted, uses built-in schema detection.",
    )
    parser.add_argument(
        "--builtin-schema",
        choices=list(EXAMPLE_SCHEMAS.keys()),
        default=None,
        metavar="NAME",
        help=(
            "Use a built-in schema by name instead of a file. "
            f"Choices: {', '.join(EXAMPLE_SCHEMAS.keys())}"
        ),
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=15,
        metavar="SECONDS",
        help="HTTP request timeout in seconds",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Print the full response body",
    )
    parser.add_argument(
        "--header",
        action="append",
        default=[],
        metavar="KEY:VALUE",
        help="Extra HTTP headers (repeatable), e.g. --header 'Authorization: Bearer TOKEN'",
    )
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)

    # ---- Resolve schema ----
    schema = None
    schema_source = ""

    if args.schema:
        try:
            schema = load_schema(args.schema)
            schema_source = f"file '{args.schema}'"
        except (FileNotFoundError, ValueError) as exc:
            print(f"[ERROR] {exc}", file=sys.stderr)
            return 2

    elif args.builtin_schema:
        schema = EXAMPLE_SCHEMAS[args.builtin_schema]
        schema_source = f"built-in '{args.builtin_schema}'"

    else:
        print(
            "[ERROR] You must provide --schema FILE or --builtin-schema NAME.\n"
            f"  Built-in schemas available: {', '.join(EXAMPLE_SCHEMAS.keys())}",
            file=sys.stderr,
        )
        return 2

    # Verify schema is itself valid
    try:
        Draft7Validator.check_schema(schema)
    except SchemaError as exc:
        print(f"[ERROR] The provided schema is invalid: {exc.message}", file=sys.stderr)
        return 2

    # ---- Parse extra headers ----
    headers = {}
    for h in args.header:
        if ":" not in h:
            print(f"[WARN] Ignoring malformed header (no colon): '{h}'", file=sys.stderr)
            continue
        key, _, value = h.partition(":")
        headers[key.strip()] = value.strip()

    # ---- Fetch URL ----
    print(f"\nFetching: {args.url}")
    try:
        data, status_code = fetch_response(args.url, args.timeout, headers)
    except requests.exceptions.Timeout:
        print(f"[FAIL] Request timed out after {args.timeout}s.")
        return 1
    except requests.exceptions.HTTPError as exc:
        print(f"[FAIL] HTTP error: {exc}")
        return 1
    except requests.exceptions.ConnectionError as exc:
        print(f"[FAIL] Connection error: {exc}")
        return 1
    except ValueError as exc:
        print(f"[FAIL] Response is not valid JSON: {exc}")
        return 1

    print(f"Status code: {status_code}")

    if args.verbose:
        print("\nResponse body:")
        print(json.dumps(data, indent=2, ensure_ascii=False))

    # ---- Validate ----
    print(f"\nValidating against schema: {schema_source}")
    errors = validate_against_schema(data, schema)

    if errors:
        print(f"\n[FAIL] Schema validation FAILED — {len(errors)} error(s):\n")
        for err in errors:
            print(err)
        print()
        return 1

    print("\n[PASS] Schema validation PASSED — response matches schema.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
