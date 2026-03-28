#!/usr/bin/env python3
"""
api_health_check.py — Check health of multiple public API endpoints.

Usage:
    python api_health_check.py
    python api_health_check.py --timeout 10
    python api_health_check.py --timeout 5 --endpoints https://jsonplaceholder.typicode.com/posts/1
"""

import argparse
import sys
import time

import requests
from rich.console import Console
from rich.table import Table
from rich import box

ENDPOINTS = [
    {
        "name": "JSONPlaceholder — GET post",
        "url": "https://jsonplaceholder.typicode.com/posts/1",
        "method": "GET",
        "expected_status": 200,
    },
    {
        "name": "JSONPlaceholder — GET users",
        "url": "https://jsonplaceholder.typicode.com/users",
        "method": "GET",
        "expected_status": 200,
    },
    {
        "name": "ReqRes — GET users",
        "url": "https://reqres.in/api/users?page=1",
        "method": "GET",
        "expected_status": 200,
    },
    {
        "name": "ReqRes — GET single user",
        "url": "https://reqres.in/api/users/2",
        "method": "GET",
        "expected_status": 200,
    },
    {
        "name": "httpbin — GET /get",
        "url": "https://httpbin.org/get",
        "method": "GET",
        "expected_status": 200,
    },
    {
        "name": "httpbin — GET /status/200",
        "url": "https://httpbin.org/status/200",
        "method": "GET",
        "expected_status": 200,
    },
    {
        "name": "httpbin — GET /json",
        "url": "https://httpbin.org/json",
        "method": "GET",
        "expected_status": 200,
    },
]


def check_endpoint(endpoint: dict, timeout: int) -> dict:
    """Perform an HTTP request and return a result dict."""
    url = endpoint["url"]
    method = endpoint.get("method", "GET")
    expected_status = endpoint.get("expected_status", 200)

    start = time.monotonic()
    try:
        response = requests.request(method, url, timeout=timeout)
        elapsed_ms = (time.monotonic() - start) * 1000
        status_code = response.status_code
        passed = status_code == expected_status
        error = None
    except requests.exceptions.Timeout:
        elapsed_ms = timeout * 1000
        status_code = None
        passed = False
        error = f"Timed out after {timeout}s"
    except requests.exceptions.ConnectionError as exc:
        elapsed_ms = (time.monotonic() - start) * 1000
        status_code = None
        passed = False
        error = f"Connection error: {exc}"
    except requests.exceptions.RequestException as exc:
        elapsed_ms = (time.monotonic() - start) * 1000
        status_code = None
        passed = False
        error = str(exc)

    return {
        "name": endpoint["name"],
        "url": url,
        "method": method,
        "expected_status": expected_status,
        "status_code": status_code,
        "elapsed_ms": elapsed_ms,
        "passed": passed,
        "error": error,
    }


def build_table(results: list[dict]) -> Table:
    """Build a Rich table from result dicts."""
    table = Table(
        title="API Health Check Results",
        box=box.ROUNDED,
        show_lines=True,
        highlight=True,
    )

    table.add_column("Endpoint", style="bold cyan", no_wrap=False, min_width=30)
    table.add_column("URL", style="dim", no_wrap=False, min_width=35)
    table.add_column("Method", justify="center", style="magenta", min_width=6)
    table.add_column("Status", justify="center", min_width=7)
    table.add_column("Expected", justify="center", min_width=8)
    table.add_column("Time (ms)", justify="right", min_width=9)
    table.add_column("Result", justify="center", min_width=8)

    for r in results:
        status_str = str(r["status_code"]) if r["status_code"] is not None else "N/A"
        status_style = "green" if r["passed"] else "red"

        elapsed_str = f"{r['elapsed_ms']:.1f}"
        elapsed_style = (
            "green" if r["elapsed_ms"] < 500
            else "yellow" if r["elapsed_ms"] < 2000
            else "red"
        )

        result_str = "[green]PASS[/green]" if r["passed"] else "[red]FAIL[/red]"

        detail = r["url"]
        if r["error"]:
            detail = f"{r['url']}\n[red]{r['error']}[/red]"

        table.add_row(
            r["name"],
            detail,
            r["method"],
            f"[{status_style}]{status_str}[/{status_style}]",
            str(r["expected_status"]),
            f"[{elapsed_style}]{elapsed_str}[/{elapsed_style}]",
            result_str,
        )

    return table


def parse_args(argv=None):
    parser = argparse.ArgumentParser(
        description="Check health of multiple public API endpoints.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=15,
        metavar="SECONDS",
        help="Request timeout in seconds",
    )
    parser.add_argument(
        "--endpoints",
        nargs="*",
        metavar="URL",
        help="Override the built-in endpoint list with custom URLs (GET, expect 200)",
    )
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_args(argv)
    console = Console()

    if args.endpoints:
        endpoint_list = [
            {
                "name": url,
                "url": url,
                "method": "GET",
                "expected_status": 200,
            }
            for url in args.endpoints
        ]
    else:
        endpoint_list = ENDPOINTS

    console.print(
        f"\n[bold]Running health checks against [cyan]{len(endpoint_list)}[/cyan] endpoint(s) "
        f"with timeout=[yellow]{args.timeout}s[/yellow][/bold]\n"
    )

    results = []
    for ep in endpoint_list:
        console.print(f"  Checking [cyan]{ep['name']}[/cyan] …", end=" ")
        result = check_endpoint(ep, args.timeout)
        results.append(result)
        status = "[green]done[/green]" if result["passed"] else "[red]failed[/red]"
        console.print(status)

    console.print()
    console.print(build_table(results))

    total = len(results)
    passed = sum(1 for r in results if r["passed"])
    failed = total - passed

    console.print(
        f"\n[bold]Summary:[/bold] "
        f"[green]{passed} passed[/green] / "
        f"[red]{failed} failed[/red] / "
        f"{total} total\n"
    )

    if failed > 0:
        console.print(
            "[bold red]One or more endpoints failed. Exiting with code 1.[/bold red]\n"
        )
        return 1

    console.print("[bold green]All endpoints healthy.[/bold green]\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
