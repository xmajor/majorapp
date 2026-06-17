#!/usr/bin/env python3
"""Apify API wrapper — LinkedIn post, engager, and profile scraping."""

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


def run_actor(actor_id: str, run_input: dict, timeout_secs: int = 300) -> list:
    """Run an Apify actor synchronously and return dataset items."""
    headers = {"Authorization": f"Bearer {_token()}"}

    resp = requests.post(
        f"{APIFY_BASE}/acts/{actor_id}/runs",
        headers=headers,
        json={"input": run_input, "options": {"timeoutSecs": timeout_secs}},
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
        raise RuntimeError(f"Apify actor run {run_id} finished with status: {status}")

    items_resp = requests.get(
        f"{APIFY_BASE}/datasets/{dataset_id}/items",
        headers=headers,
        params={"format": "json", "clean": "true"},
        timeout=60,
    )
    items_resp.raise_for_status()
    return items_resp.json()


def get_linkedin_posts(profile_urls: list, days_back: int | None = None) -> list:
    """Scrape recent posts from LinkedIn profile URLs."""
    cfg = _config()
    actor = cfg["apify"]["actors"]["post_scraper"]
    if days_back is None:
        days_back = cfg["apify"]["days_back"]
    return run_actor(
        actor,
        {
            "profileUrls": profile_urls,
            "maxPostsPerProfile": cfg["apify"]["max_posts_per_profile"],
            "daysBack": days_back,
        },
        timeout_secs=cfg["apify"]["actor_timeout_secs"],
    )


def get_post_engagers(post_urls: list) -> list:
    """Scrape likers and commenters from LinkedIn post URLs."""
    cfg = _config()
    actor = cfg["apify"]["actors"]["engager_scraper"]
    return run_actor(
        actor,
        {
            "postUrls": post_urls,
            "maxEngagersPerPost": cfg["apify"]["max_engagers_per_post"],
        },
        timeout_secs=cfg["apify"]["actor_timeout_secs"],
    )


def get_profile_details(profile_urls: list) -> list:
    """Fetch enriched profile data for a list of LinkedIn URLs."""
    cfg = _config()
    actor = cfg["apify"]["actors"]["profile_scraper"]
    batch_size = cfg["apify"]["profile_batch_size"]
    results = []
    for i in range(0, len(profile_urls), batch_size):
        batch = profile_urls[i : i + batch_size]
        results.extend(
            run_actor(
                actor,
                {"profileUrls": batch},
                timeout_secs=cfg["apify"]["actor_timeout_secs"],
            )
        )
    return results
