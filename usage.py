#!/usr/bin/env python3
"""Read-only adapter for this user's Wakapi dashboard API. No third-party deps."""
from __future__ import annotations

import argparse
import base64
from concurrent.futures import ThreadPoolExecutor, as_completed
import configparser
from datetime import datetime
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import time
import urllib.error
import urllib.parse
import urllib.request

MAX_BYTES = 4 * 1024 * 1024
MAX_ROWS = 10000
PERIODS = {"1d": "days=1", "7d": "days=7", "30d": "days=30", "all": "interval=all_time"}
ENDPOINTS = ("overview", "tokens", "activity", "projects", "breakdown", "agents", "machines")


class DataError(Exception):
    pass


def number(value, *, integer=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise DataError("invalid_number")
    if not math.isfinite(value) or value < 0 or value > 10**15:
        raise DataError("invalid_number")
    if integer and int(value) != value:
        raise DataError("invalid_number")
    return int(value) if integer else value


def label(value):
    if not isinstance(value, str) or len(value) > 4096:
        raise DataError("invalid_label")
    return re.sub(r"[\x00-\x1f\x7f]", " ", value)[:160]


def rows(value):
    if not isinstance(value, list) or len(value) > MAX_ROWS:
        raise DataError("invalid_collection")
    return value


def timestamp(value):
    value = label(value)
    try:
        date = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if date.tzinfo is None or not 1970 <= date.year <= 2100:
            raise ValueError()
    except ValueError:
        raise DataError("invalid_timestamp") from None
    return value


def token_counts(raw):
    keys = ("input", "cached_input", "cache_write", "unknown_input", "output", "total")
    out = {k: number(raw[k], integer=True) for k in keys}
    if sum(out[k] for k in keys[:-1]) != out["total"]:
        raise DataError("token_total_mismatch")
    return out


def bars(raw, name="name", metric="seconds"):
    out = [{"name": label(r[name]), "value": number(r[metric])} for r in rows(raw)]
    return sorted(out, key=lambda r: (-r["value"], r["name"]))


def heatmap(raw):
    if len(rows(raw)) != 7 or any(len(rows(day)) != 24 for day in raw):
        raise DataError("invalid_heatmap")
    return [number(v) for day in raw for v in day]


def trend(raw):
    out = []
    for r in rows(raw):
        date = label(r["date"])
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", date):
            raise DataError("invalid_date")
        datetime.strptime(date, "%Y-%m-%d")
        out.append({"date": date, "value": number(r["tokens"]["total"], integer=True)})
    # Keep all-time charts legible without discarding older days or their counts.
    step = max(1, math.ceil(len(out) / 60))
    return [{"date": out[i]["date"], "end": out[min(i + step, len(out)) - 1]["date"],
             "value": sum(d["value"] for d in out[i:i+step])} for i in range(0, len(out), step)]


def normalize(endpoint, raw):
    if not isinstance(raw, dict):
        raise DataError("invalid_response")
    if endpoint in {"overview", "tokens", "activity", "projects", "agents"}:
        if raw.get("token_source") != "ledger":
            raise DataError("ledger_required")
    if endpoint == "overview":
        activity = raw["time"]
        cost = raw["cost"]
        return {
            "range": {k: timestamp(raw["range"][k]) for k in ("from", "to")},
            "tokens": token_counts(raw["tokens"]),
            "time": {k: number(activity[k]) for k in ("total_seconds", "you_seconds", "agent_seconds", "overlap_seconds")},
            "cost": ({"value": number(cost["estimated_api_value"]), "currency": label(cost["currency"]),
                      "priced": number(cost["priced_tokens"], integer=True),
                      "unpriced": number(cost["unpriced_tokens"], integer=True)} if cost.get("available") else None),
            "notes": [label(s) for s in rows(raw.get("coverage_notes", []))][:20],
        }
    if endpoint == "tokens":
        models = raw["by_model"]
        if not isinstance(models, dict) or len(models) > MAX_ROWS:
            raise DataError("invalid_models")
        return {"totals": token_counts(raw["totals"]), "days": trend(raw["by_day"]),
                "models": sorted([{"name": label(k), "value": token_counts(v)["total"]}
                                  for k, v in models.items() if token_counts(v)["total"] > 0], key=lambda r: -r["value"])}
    if endpoint == "projects":
        return sorted([{"name": label(r["name"]), "value": number(r["tokens"], integer=True),
                        "seconds": number(r["seconds"])} for r in rows(raw["projects"])], key=lambda r: -r["value"])
    if endpoint == "activity":
        stats = raw["sessions"]
        return {"share": bars(raw["share"], name="group"),
                "sessions": number(stats["sessions"], integer=True),
                "active_days": number(stats["active_days"], integer=True),
                "median_seconds": number(stats["median_session_seconds"])}
    if endpoint == "breakdown":
        return {"agents": heatmap(raw["rhythm_agents"]), "you": heatmap(raw["rhythm_you"]),
                "streak": number(raw["streak_days"], integer=True),
                "average": number(raw["daily_average_seconds"]),
                **{k: bars(raw[k]) for k in ("languages", "editors", "categories")}}
    if endpoint == "agents":
        return [{"name": label(r["group"]), "value": number(r["tokens"], integer=True),
                 "seconds": number(r["seconds"]), "lines": number(r["line_changes"], integer=True),
                 "sessions": number(r["sessions"], integer=True)} for r in rows(raw["agents"])]
    if endpoint == "machines":
        return [{"name": label(r["name"]), "os": label(r["os"]), "last_seen": timestamp(r["last_seen"]),
                 "live": r["live"] is True, "agent": label(r["active_agent"])} for r in rows(raw["machines"])][:20]
    raise DataError("unknown_endpoint")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None  # Never forward credentials to another destination.


def connection():
    conf = configparser.ConfigParser(interpolation=None)
    conf.read(Path.home() / ".wakatime.cfg")
    # An s-injected key can override the existing WakaTime key without writing it.
    base = os.environ.get("WAKAPI_API_URL") or conf.get("settings", "api_url", fallback="")
    key = os.environ.get("WAKAPI_API_KEY") or conf.get("settings", "api_key", fallback="")
    parsed = urllib.parse.urlsplit(base)
    loopback = parsed.scheme == "http" and parsed.hostname in ("127.0.0.1", "localhost", "::1")
    if (parsed.scheme != "https" and not loopback) or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise DataError("https_configuration_required")
    if not key or len(key) > 4096:
        raise DataError("credentials_missing")
    return base.rstrip("/"), key


def fetch(base, key, endpoint, period):
    auth = "Basic " + base64.b64encode(key.encode()).decode()
    req = urllib.request.Request(base + "/dashboard/" + endpoint + "?" + PERIODS[period],
                                 headers={"Authorization": auth, "Accept": "application/json"})
    try:
        with urllib.request.build_opener(NoRedirect()).open(req, timeout=15) as response:
            body = response.read(MAX_BYTES + 1)
        if len(body) > MAX_BYTES:
            raise DataError("response_too_large")
        return normalize(endpoint, json.loads(body))
    except urllib.error.HTTPError as e:
        raise DataError("http_" + str(e.code)) from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise DataError("unreachable") from None
    except (ValueError, KeyError, TypeError, OverflowError):
        raise DataError("invalid_response") from None


def collect(base, key, period, summary=False):
    data, errors = {}, []
    endpoints = ("overview",) if summary else ENDPOINTS
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = {pool.submit(fetch, base, key, ep, period): ep for ep in endpoints}
        for future in as_completed(futures):
            ep = futures[future]
            try:
                data[ep] = future.result()
            except DataError as e:
                errors.append(ep + ":" + str(e))
    return {"period": period, "status": "error" if "overview" not in data else "partial" if errors else "ok",
            "fetched_at": int(time.time()), "data": data, "errors": sorted(errors)}


def cached_collect(base, key, period, summary=False, refresh=False, cache_root=None):
    identity = hashlib.sha256((base + "\0" + key).encode()).hexdigest()[:24]
    root = cache_root or Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "omarchy-token-usage"
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(root, 0o700)
    path = root / f"{identity}-{period}-{'summary' if summary else 'full'}.json"
    with (root / "refresh.lock").open("a+") as lock:
        os.chmod(root / "refresh.lock", 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        cached = None
        try:
            if path.stat().st_size <= MAX_BYTES:
                cached = json.loads(path.read_text())
            if cached and not refresh and time.time() - cached["fetched_at"] < 60:
                # Expire yesterday's today view at the server's local midnight.
                end = datetime.fromisoformat(cached["data"]["overview"]["range"]["to"]).timestamp()
                if time.time() < end:
                    return cached
        except (OSError, ValueError, KeyError, TypeError):
            cached = None
        fresh = collect(base, key, period, summary)
        if fresh["status"] == "ok":
            temporary = path.with_suffix(".tmp")
            fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w") as stream:
                json.dump(fresh, stream, allow_nan=False)
            os.replace(temporary, path)
        elif fresh["status"] == "error" and cached:
            cached = dict(cached, status="stale", errors=fresh["errors"])
            return cached
        return fresh


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--range", choices=PERIODS, default="1d")
    parser.add_argument("--summary", action="store_true")
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()
    try:
        result = cached_collect(*connection(), args.range, args.summary, args.refresh)
    except (DataError, OSError, configparser.Error):
        result = {"period": args.range, "status": "error", "fetched_at": 0, "data": {}, "errors": ["configuration_or_cache_unavailable"]}
    print(json.dumps(result, allow_nan=False, separators=(",", ":")))


if __name__ == "__main__":
    main()
