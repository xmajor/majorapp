#!/usr/bin/env python3
"""HeyReach API wrapper — enroll leads, read inbox, send replies, stop sequences."""

import os
import json
import pathlib
import requests

_cfg = None


def _config() -> dict:
    global _cfg
    if _cfg is None:
        _cfg = json.loads(pathlib.Path("config/pipeline.json").read_text())
    return _cfg


def _api_key() -> str:
    key = os.environ.get("HEYREACH_API_KEY", "")
    if not key:
        raise EnvironmentError("HEYREACH_API_KEY environment variable is not set.")
    return key


def _headers() -> dict:
    return {
        "X-API-KEY":    _api_key(),
        "Content-Type": "application/json",
        "Accept":       "application/json",
    }


def _base() -> str:
    return _config()["heyreach"]["base_url"].rstrip("/")


def _r(method: str, path: str, **kwargs) -> dict:
    url  = f"{_base()}{path}"
    resp = requests.request(method, url, headers=_headers(), timeout=30, **kwargs)
    resp.raise_for_status()
    return resp.json() if resp.content else {}


# ── Lead enrollment ───────────────────────────────────────────────────────────

def add_lead_to_campaign(
    lead: dict,
    campaign_id: str,
    list_id: str,
    first_message: str = "",
) -> bool:
    """Add a lead to a HeyReach campaign list and enroll them in the sequence.

    Returns True on success, False on error (caller should log and continue).
    """
    payload = {
        "leads": [
            {
                "firstName":    lead.get("firstName", ""),
                "lastName":     lead.get("lastName", ""),
                "linkedInUrl":  lead.get("profileUrl", ""),
                "companyName":  lead.get("company", ""),
                "jobTitle":     lead.get("headline", ""),
                "customVar1":   lead.get("source_influencer", ""),
                "customVar2":   lead.get("scoring", {}).get("angle", ""),
                "firstMessage": first_message,
            }
        ]
    }
    try:
        _r("POST", f"/api/v1/lists/{list_id}/leads", json=payload)
        _r("POST", f"/api/v1/campaigns/{campaign_id}/leads", json={
            "listId":   list_id,
            "linkedInUrl": lead.get("profileUrl", ""),
        })
        return True
    except requests.HTTPError as exc:
        print(f"[heyreach] enroll failed for {lead.get('profileUrl')}: {exc}")
        return False


# ── Inbox ─────────────────────────────────────────────────────────────────────

def get_inbox_messages(since_hours: int = 2) -> list:
    """Fetch unread inbox messages from the last N hours.

    Returns a list of message dicts with at minimum:
        messageId, leadId, profileUrl, firstName, lastName,
        company, text, receivedAt
    """
    import datetime
    since_dt  = datetime.datetime.utcnow() - datetime.timedelta(hours=since_hours)
    since_iso = since_dt.strftime("%Y-%m-%dT%H:%M:%SZ")

    try:
        data = _r("GET", "/api/v1/inbox/messages", params={"since": since_iso, "unread": "true"})
        return data.get("messages", data) if isinstance(data, dict) else data
    except requests.HTTPError as exc:
        print(f"[heyreach] inbox fetch failed: {exc}")
        return []


def reply_to_message(message_id: str, body: str) -> bool:
    """Send a reply to an inbox message. Returns True on success."""
    try:
        _r("POST", f"/api/v1/inbox/messages/{message_id}/reply", json={"text": body})
        return True
    except requests.HTTPError as exc:
        print(f"[heyreach] reply failed for message {message_id}: {exc}")
        return False


def stop_sequence(lead_id: str, campaign_id: str | None = None) -> bool:
    """Stop the HeyReach sequence for a lead (opt-out). Returns True on success."""
    cfg = _config()
    if campaign_id is None:
        campaign_id = cfg["heyreach"]["campaign_id_tier_a"]
    try:
        _r("POST", f"/api/v1/campaigns/{campaign_id}/leads/{lead_id}/stop")
        return True
    except requests.HTTPError as exc:
        print(f"[heyreach] stop_sequence failed for lead {lead_id}: {exc}")
        return False
