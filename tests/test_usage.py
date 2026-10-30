import copy
from datetime import date, timedelta
import io
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import urllib.error

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import usage


def tokens():
    return dict(input=10, cached_input=20, cache_write=30, unknown_input=40, output=50, total=150)


def overview():
    return dict(token_source="ledger", range={"from": "2026-10-27T00:00:00-04:00", "to": "2099-10-28T00:00:00-04:00"},
                tokens=tokens(), time=dict(total_seconds=100, you_seconds=40, agent_seconds=80, overlap_seconds=20),
                cost=dict(available=True, estimated_api_value=0.04, currency="USD", priced_tokens=110, unpriced_tokens=40),
                coverage_notes=["Provisional usage"])


class UsageTests(unittest.TestCase):
    def test_tokens_count_all_input_buckets_and_output_once(self):
        raw = tokens() | {"reasoning": 10}
        result = usage.token_counts(raw)
        self.assertEqual(result["total"], 150)
        self.assertNotIn("reasoning", result)
        with self.assertRaises(usage.DataError):
            usage.token_counts(raw | {"total": 160})

    def test_rejects_malformed_counts_and_unbounded_data(self):
        for value in (-1, True, "20", float("nan"), float("inf"), 10**16, 2.5):
            with self.subTest(value=value), self.assertRaises(usage.DataError):
                usage.number(value, integer=True)
        with self.assertRaises(usage.DataError):
            usage.rows([0] * (usage.MAX_ROWS + 1))
        with self.assertRaises(usage.DataError):
            usage.heatmap([[0] * 24] * 8)

    def test_markup_stays_data_and_labels_are_bounded(self):
        name = '<img src="https://example.invalid/tracker">'
        result = usage.bars([{"name": name, "seconds": 60}])
        self.assertEqual(result[0]["name"], name)
        self.assertEqual(usage.label("a\nb"), "a b")
        self.assertEqual(len(usage.label("x" * 300)), 160)

    def test_deployment_cannot_silently_switch_to_legacy_tokens(self):
        for source in (None, "heartbeats"):
            with self.subTest(source=source), self.assertRaisesRegex(usage.DataError, "ledger_required"):
                usage.normalize("overview", overview() | {"token_source": source})

    def test_all_time_trend_preserves_every_day_and_total(self):
        raw = [{"date": str(date(2024, 1, 1) + timedelta(days=n)), "tokens": {"total": n}} for n in range(1201)]
        result = usage.trend(raw)
        self.assertLessEqual(len(result), 60)
        self.assertEqual(sum(r["value"] for r in result), sum(range(1201)))
        self.assertEqual(result[0]["date"], raw[0]["date"])
        self.assertEqual(result[-1]["end"], raw[-1]["date"])

    def test_empty_period_has_real_zero_counts(self):
        raw = {"token_source": "ledger", "totals": {k: 0 for k in tokens()}, "by_day": [], "by_model": {}}
        self.assertEqual(usage.normalize("tokens", raw), {"totals": raw["totals"], "days": [], "models": []})

    def test_missing_section_does_not_become_zero(self):
        def fake_fetch(base, key, endpoint, period):
            if endpoint == "overview":
                return usage.normalize(endpoint, overview())
            raise usage.DataError("unreachable")
        with patch.object(usage, "fetch", side_effect=fake_fetch):
            result = usage.collect("https://example.invalid/api", "not-a-real-key", "7d")
        self.assertEqual(result["status"], "partial")
        self.assertNotIn("tokens", result["data"])
        self.assertEqual(len(result["errors"]), 6)

    def test_cached_snapshot_is_marked_stale_and_does_not_cross_ranges(self):
        good = {"period": "7d", "status": "ok", "fetched_at": int(time.time()),
                "data": {"overview": usage.normalize("overview", overview())}, "errors": []}
        failed = {"period": "7d", "status": "error", "data": {}, "errors": ["overview:unreachable"]}
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(usage, "collect", return_value=good) as collect:
                usage.cached_collect("https://example.invalid/api", "test-key", "7d", cache_root=root)
                cached = usage.cached_collect("https://example.invalid/api", "test-key", "7d", cache_root=root)
                self.assertEqual(collect.call_count, 1)
                self.assertEqual(cached["status"], "ok")
            for p in root.glob("*.json"):
                self.assertEqual(p.stat().st_mode & 0o777, 0o600)
            with patch.object(usage, "collect", return_value=failed):
                stale = usage.cached_collect("https://example.invalid/api", "test-key", "7d", refresh=True, cache_root=root)
                other = usage.cached_collect("https://example.invalid/api", "test-key", "30d", cache_root=root)
                account = usage.cached_collect("https://example.invalid/api", "other-key", "7d", cache_root=root)
            self.assertEqual(stale["status"], "stale")
            self.assertEqual(stale["fetched_at"], good["fetched_at"])
            self.assertEqual(other["status"], "error")
            self.assertEqual(account["status"], "error")

    def test_whole_calendar_day_ranges_are_delegated_to_wakapi(self):
        self.assertEqual(usage.PERIODS, {"1d": "days=1", "7d": "days=7", "30d": "days=30", "all": "interval=all_time"})

    def test_connection_needs_https_except_on_loopback(self):
        for url, ok in (("https://wakapi.example/api", True), ("http://127.0.0.1:3100/api", True),
                        ("http://localhost:3100/api", True), ("http://wakapi.example/api", False),
                        ("https://user:pw@wakapi.example/api", False)):
            with patch.dict(usage.os.environ, {"WAKAPI_API_URL": url, "WAKAPI_API_KEY": "k"}):
                if ok:
                    self.assertEqual(usage.connection()[0], url.rstrip("/"))
                else:
                    with self.assertRaises(usage.DataError):
                        usage.connection()

    def test_redirects_are_never_followed(self):
        self.assertIsNone(usage.NoRedirect().redirect_request(None, None, 302, "", {}, "https://other.invalid"))

    def test_fetch_hides_http_body_and_rejects_oversized_response(self):
        class Response(io.BytesIO):
            def __enter__(self): return self
            def __exit__(self, *args): self.close()
        class Opener:
            def open(self, request, timeout):
                return Response(b" " * (usage.MAX_BYTES + 1))
        with patch.object(usage.urllib.request, "build_opener", return_value=Opener()):
            with self.assertRaisesRegex(usage.DataError, "response_too_large"):
                usage.fetch("https://example.invalid/api", "test-key", "tokens", "1d")


if __name__ == "__main__":
    unittest.main()
