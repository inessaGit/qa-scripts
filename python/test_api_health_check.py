#!/usr/bin/env python3
"""
test_api_health_check.py — pytest tests for api_health_check.py

Uses unittest.mock to patch requests.request so no real HTTP calls are made.

Run:
    pytest python/test_api_health_check.py -v
    pytest python/test_api_health_check.py -v --tb=short
"""

import sys
import time
from io import StringIO
from unittest.mock import MagicMock, patch, call

import pytest

# Allow running from repo root or from python/ directory
import importlib.util
from pathlib import Path

_script_path = Path(__file__).parent / "api_health_check.py"
_spec = importlib.util.spec_from_file_location("api_health_check", _script_path)
_module = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_module)

check_endpoint = _module.check_endpoint
build_table = _module.build_table
main = _module.main
ENDPOINTS = _module.ENDPOINTS


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_response(status_code: int, json_data: dict | None = None) -> MagicMock:
    """Create a mock requests.Response object."""
    mock_resp = MagicMock()
    mock_resp.status_code = status_code
    mock_resp.json.return_value = json_data or {}
    return mock_resp


# ---------------------------------------------------------------------------
# Tests for check_endpoint()
# ---------------------------------------------------------------------------

class TestCheckEndpoint:
    """Unit tests for the check_endpoint() function."""

    def test_successful_200_response(self):
        """Endpoint returning 200 when 200 is expected should PASS."""
        endpoint = {
            "name": "Test endpoint",
            "url": "https://example.com/api",
            "method": "GET",
            "expected_status": 200,
        }
        mock_resp = _make_response(200)
        with patch("requests.request", return_value=mock_resp) as mock_req:
            result = check_endpoint(endpoint, timeout=5)

        mock_req.assert_called_once_with("GET", "https://example.com/api", timeout=5)
        assert result["passed"] is True
        assert result["status_code"] == 200
        assert result["error"] is None
        assert result["elapsed_ms"] >= 0

    def test_unexpected_status_code_fails(self):
        """Endpoint returning 404 when 200 is expected should FAIL."""
        endpoint = {
            "name": "Not found",
            "url": "https://example.com/missing",
            "method": "GET",
            "expected_status": 200,
        }
        mock_resp = _make_response(404)
        with patch("requests.request", return_value=mock_resp):
            result = check_endpoint(endpoint, timeout=5)

        assert result["passed"] is False
        assert result["status_code"] == 404

    def test_expected_404_passes(self):
        """Endpoint returning 404 when 404 is expected should PASS."""
        endpoint = {
            "name": "Deliberately absent",
            "url": "https://example.com/gone",
            "method": "GET",
            "expected_status": 404,
        }
        mock_resp = _make_response(404)
        with patch("requests.request", return_value=mock_resp):
            result = check_endpoint(endpoint, timeout=5)

        assert result["passed"] is True
        assert result["status_code"] == 404

    def test_timeout_exception_sets_failed(self):
        """A Timeout exception should mark the endpoint as FAIL."""
        import requests as req_mod

        endpoint = {
            "name": "Slow endpoint",
            "url": "https://example.com/slow",
            "method": "GET",
            "expected_status": 200,
        }
        with patch("requests.request", side_effect=req_mod.exceptions.Timeout()):
            result = check_endpoint(endpoint, timeout=3)

        assert result["passed"] is False
        assert result["status_code"] is None
        assert "Timed out" in result["error"]

    def test_connection_error_sets_failed(self):
        """A ConnectionError exception should mark the endpoint as FAIL."""
        import requests as req_mod

        endpoint = {
            "name": "Unreachable",
            "url": "https://unreachable.invalid/api",
            "method": "GET",
            "expected_status": 200,
        }
        with patch("requests.request", side_effect=req_mod.exceptions.ConnectionError("refused")):
            result = check_endpoint(endpoint, timeout=5)

        assert result["passed"] is False
        assert result["status_code"] is None
        assert "Connection error" in result["error"]

    def test_generic_request_exception(self):
        """A generic RequestException should mark the endpoint as FAIL."""
        import requests as req_mod

        endpoint = {
            "name": "Broken",
            "url": "https://example.com/broken",
            "method": "GET",
            "expected_status": 200,
        }
        with patch("requests.request", side_effect=req_mod.exceptions.RequestException("oops")):
            result = check_endpoint(endpoint, timeout=5)

        assert result["passed"] is False
        assert "oops" in result["error"]

    def test_result_contains_expected_keys(self):
        """Result dict must always contain all required keys."""
        endpoint = {
            "name": "Key check",
            "url": "https://example.com/api",
            "method": "GET",
            "expected_status": 200,
        }
        mock_resp = _make_response(200)
        with patch("requests.request", return_value=mock_resp):
            result = check_endpoint(endpoint, timeout=5)

        for key in ("name", "url", "method", "expected_status",
                    "status_code", "elapsed_ms", "passed", "error"):
            assert key in result, f"Missing key: {key}"

    def test_elapsed_time_is_positive(self):
        """Elapsed time should always be a non-negative float."""
        endpoint = {
            "name": "Timer check",
            "url": "https://example.com/api",
            "method": "GET",
            "expected_status": 200,
        }
        mock_resp = _make_response(200)
        with patch("requests.request", return_value=mock_resp):
            result = check_endpoint(endpoint, timeout=5)

        assert isinstance(result["elapsed_ms"], float)
        assert result["elapsed_ms"] >= 0

    def test_post_method_is_forwarded(self):
        """Method field should be forwarded to requests.request."""
        endpoint = {
            "name": "POST endpoint",
            "url": "https://example.com/api/create",
            "method": "POST",
            "expected_status": 201,
        }
        mock_resp = _make_response(201)
        with patch("requests.request", return_value=mock_resp) as mock_req:
            result = check_endpoint(endpoint, timeout=5)

        mock_req.assert_called_once_with("POST", "https://example.com/api/create", timeout=5)
        assert result["passed"] is True


# ---------------------------------------------------------------------------
# Tests for build_table()
# ---------------------------------------------------------------------------

class TestBuildTable:
    """Unit tests for the build_table() function."""

    def _make_results(self, passed_flags: list[bool]) -> list[dict]:
        return [
            {
                "name": f"Endpoint {i}",
                "url": f"https://example.com/ep{i}",
                "method": "GET",
                "expected_status": 200,
                "status_code": 200 if p else 500,
                "elapsed_ms": 123.4,
                "passed": p,
                "error": None,
            }
            for i, p in enumerate(passed_flags)
        ]

    def test_returns_table_object(self):
        from rich.table import Table
        results = self._make_results([True, False])
        table = build_table(results)
        assert isinstance(table, Table)

    def test_table_row_count_matches_results(self):
        results = self._make_results([True, True, False])
        table = build_table(results)
        assert table.row_count == 3

    def test_empty_results_produces_empty_table(self):
        table = build_table([])
        assert table.row_count == 0

    def test_table_has_seven_columns(self):
        results = self._make_results([True])
        table = build_table(results)
        assert len(table.columns) == 7

    def test_error_message_reflected_in_table(self):
        """Rows with errors should still be added (the error appears in URL cell)."""
        results = [
            {
                "name": "Broken",
                "url": "https://example.com",
                "method": "GET",
                "expected_status": 200,
                "status_code": None,
                "elapsed_ms": 5000.0,
                "passed": False,
                "error": "Timed out after 5s",
            }
        ]
        table = build_table(results)
        assert table.row_count == 1


# ---------------------------------------------------------------------------
# Integration tests for main()
# ---------------------------------------------------------------------------

class TestMain:
    """Integration tests for the main() entry point."""

    def _all_pass_side_effect(self, method, url, timeout):
        return _make_response(200)

    def _all_fail_side_effect(self, method, url, timeout):
        return _make_response(500)

    def test_main_returns_0_when_all_pass(self):
        """main() should return 0 when every endpoint passes."""
        with patch("requests.request", side_effect=self._all_pass_side_effect):
            exit_code = main([])
        assert exit_code == 0

    def test_main_returns_1_when_any_fail(self):
        """main() should return 1 when any endpoint fails."""
        with patch("requests.request", side_effect=self._all_fail_side_effect):
            exit_code = main([])
        assert exit_code == 1

    def test_main_accepts_timeout_flag(self):
        """--timeout flag should be accepted without error."""
        with patch("requests.request", side_effect=self._all_pass_side_effect):
            exit_code = main(["--timeout", "20"])
        assert exit_code == 0

    def test_main_accepts_custom_endpoints(self):
        """--endpoints flag should override the built-in endpoint list."""
        with patch("requests.request", return_value=_make_response(200)) as mock_req:
            exit_code = main(["--endpoints", "https://custom.example.com/health"])

        assert exit_code == 0
        # Should only have called the one custom URL
        assert mock_req.call_count == 1
        assert mock_req.call_args[0][1] == "https://custom.example.com/health"

    def test_main_multiple_custom_endpoints(self):
        """Multiple --endpoints values should all be checked."""
        urls = [
            "https://a.example.com/health",
            "https://b.example.com/health",
            "https://c.example.com/health",
        ]
        with patch("requests.request", return_value=_make_response(200)) as mock_req:
            exit_code = main(["--endpoints"] + urls)

        assert exit_code == 0
        assert mock_req.call_count == 3

    def test_main_returns_1_on_partial_failure(self):
        """Even one failing endpoint should cause exit code 1."""
        responses = [_make_response(200), _make_response(404), _make_response(200)]
        response_iter = iter(responses)

        def side_effect(method, url, timeout):
            return next(response_iter)

        with patch("requests.request", side_effect=side_effect):
            # Only 3 custom endpoints so we consume exactly 3 responses
            exit_code = main([
                "--endpoints",
                "https://a.example.com",
                "https://b.example.com",
                "https://c.example.com",
            ])
        assert exit_code == 1

    def test_main_with_timeout_forwarded_to_requests(self):
        """The timeout value should be passed through to requests.request."""
        with patch("requests.request", return_value=_make_response(200)) as mock_req:
            main(["--endpoints", "https://example.com/api", "--timeout", "7"])

        _, kwargs_or_args = mock_req.call_args[0], mock_req.call_args
        # timeout is a positional or keyword arg — check either way
        call_kwargs = mock_req.call_args[1]
        assert call_kwargs.get("timeout") == 7


# ---------------------------------------------------------------------------
# Tests for built-in ENDPOINTS list
# ---------------------------------------------------------------------------

class TestBuiltinEndpoints:
    """Smoke-tests for the built-in ENDPOINTS configuration."""

    def test_endpoints_list_is_not_empty(self):
        assert len(ENDPOINTS) > 0

    def test_all_endpoints_have_required_keys(self):
        required_keys = {"name", "url", "method", "expected_status"}
        for ep in ENDPOINTS:
            missing = required_keys - ep.keys()
            assert not missing, f"Endpoint '{ep.get('name', '?')}' missing keys: {missing}"

    def test_all_urls_start_with_https(self):
        for ep in ENDPOINTS:
            assert ep["url"].startswith("https://"), (
                f"Endpoint '{ep['name']}' URL should use HTTPS: {ep['url']}"
            )

    def test_all_expected_statuses_are_valid_http_codes(self):
        for ep in ENDPOINTS:
            assert 100 <= ep["expected_status"] < 600, (
                f"Endpoint '{ep['name']}' has invalid expected_status: {ep['expected_status']}"
            )
