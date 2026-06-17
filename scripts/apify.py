#!/usr/bin/env python3
"""Apify API wrapper — LinkedIn post, engager, and profile scraping.

Each pipeline source (post / engager / profile) is configured in
config/pipeline.json under apify.sources as either a saved *task*
(pre-configured input) or a raw *actor*. The post scraper is a task.
"""

import os
import time
import json
import pathlib
import requests

APIFY_BASE = "https://api.apify.com/v2"
_cfg = None


def _config():
    global _cfg
    if _cfg is None:
        _cfg = json.loads(pathlib.Path("config/pipeline.json").read_text())
    return _cfg


def _token():
    token = os.environ.get("APIFY_TOKEN", "")
    if not token:
        raise EnvironmentError("APIFY_TOKEN environment variable is not set.")
    return token


def _run(run_path: str, run_input: dict | None, timeout_secs: int) -> list:
    """Start a run at /v2/{run_path}/runs, poll to completion, return dataset items.

    run_path is either "acts/{actor_id}" or "actor-tasks/{task_id}". For the
    Apify REST API the run input is the raw POST body and run options are query
    params. Passing an empty body to a task run uses the task's saved input.
    """
    headers = {"Authorization": f"Bearer {_token()}"}

    resp = requests.post(
        f"{APIFY_BASE}/{run_path}/runs",
        headers=headers,
        params={"timeout": timeout_secs},
        json=run_input or {},
        timeout=30,
    )
    resp.raise_for_status()
    data = resp.json()["data"]
    run_id = data["id"]
    dataset_id = data["defaultDatasetId"]

    deadline = time.time() + timeout_secs + 60
    status = "RUNNING"
    while time.time() < deadline:
        status_resp = requests.get(
            f"{APIFY_BASE}/actor-runs/{run_id}",
            headers=headers,
            timeout=15,
        )
        status_resp.raise_for_status()
        status = status_resp.json()["data"]["status"]
        if status in ("SUCCEEDED", "FAILED", "TIMED-OUT", "ABORTED"):
            break
        time.sleep(5)

    if status != "SUCCEEDED":
        raise RuntimeError(f"Apify run {run_id} finished with status: {status}")

    items_resp = requests.get(
        f"{APIFY_BASE}/datasets/{dataset_id}/items",
        headers=headers,
        params={"format": "json", "clean": "true"},
        timeout=60,
    )
    items_resp.raise_for_status()
    return items_resp.json()


def run_actor(actor_id: str, run_input: dict, timeout_secs: int = 300) -> list:
    """Run a raw actor with explicit input."""
    return _run(f"acts/{actor_id}", run_input, timeout_secs)


def run_task(task_id: str, run_input: dict | None = None, timeout_secs: int = 300) -> list:
    """Run a saved task. Pass run_input to override the task's saved input,
    or None/empty to run with the saved input as-is."""
    return _run(f"actor-tasks/{task_id}", run_input, timeout_secs)


def _run_source(source_key: str, run_input: dict, timeout_secs: int) -> list:
    """Dispatch a configured source (task or actor). Honors override_input:
    a task with override_input=false runs with its saved input."""
    src = _config()["apify"]["sources"][source_key]
    override = run_input if src.get("override_input", True) else None
    if src["type"] == "task":
        return run_task(src["id"], override, timeout_secs)
    return run_actor(src["id"], run_input, timeout_secs)


def get_linkedin_posts(profile_urls: list, days_back: int | None = None) -> list:
    """Scrape recent posts. The post scraper is a saved task; by default it runs
    with its own saved input (profile list configured in the task)."""
    cfg = _config()
    if days_back is None:
        days_back = cfg["apify"]["days_back"]
    run_input = {
        "profileUrls": profile_urls,
        "maxPostsPerProfile": cfg["apify"]["max_posts_per_profile"],
        "daysBack": days_back,
    }
    return _run_source("post_scraper", run_input, cfg["apify"]["actor_timeout_secs"])


def get_post_engagers(post_urls: list) -> list:
    """Scrape likers and commenters from LinkedIn post URLs."""
    cfg = _config()
    run_input = {
        "postUrls": post_urls,
        "maxEngagersPerPost": cfg["apify"]["max_engagers_per_post"],
    }
    return _run_source("engager_scraper", run_input, cfg["apify"]["actor_timeout_secs"])


def get_profile_details(profile_urls: list) -> list:
    """Fetch enriched profile data for a list of LinkedIn URLs (batched)."""
    cfg = _config()
    batch_size = cfg["apify"]["profile_batch_size"]
    timeout = cfg["apify"]["actor_timeout_secs"]
    results = []
    for i in range(0, len(profile_urls), batch_size):
        batch = profile_urls[i : i + batch_size]
        results.extend(_run_source("profile_scraper", {"profileUrls": batch}, timeout))
    return results
