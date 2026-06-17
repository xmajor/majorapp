#!/usr/bin/env python3
"""HeyReach public API wrapper — enroll leads, read inbox, send replies, stop leads.

Base: https://api.heyreach.io/api/public   Auth header: X-API-KEY

Notes on the HeyReach model:
- Campaign and list ids are NUMERIC.
- A campaign's message sequence is built in the HeyReach UI with template
  variables (e.g. {{firstName}}, {{message}}). You do NOT POST a literal first
  message; instead you add leads with custom fields, and the campaign template
  renders them. We compose the personalized copy in Python and pass it as the
  custom field "message" — point the campaign's first step at {{message}}.
- Adding leads to a campaign requires a sender LinkedIn account id
  (sender_linkedin_account_id in config/pipeline.json).

These endpoints were written against the HeyReach public API docs but could not
be smoke-tested from the build environment (egress to api.heyreach.io is blocked
by the network policy). Confirm request/response shapes against Settings > API.
"""

import os
import json
import pathlib
import datetime
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
    resp = requests.request(method, f"{_base()}{path}", headers=_headers(), timeout=30, **kwargs)
    resp.raise_for_status()
    return resp.json() if resp.content else {}


# ── Auth ──────────────────────────────────────────────────────────────────────

def check_api_key() -> bool:
    """Return True if the configured API key is valid."""
    try:
        _r("GET", "/auth/CheckApiKey")
        return True
    except requests.HTTPError:
        return False


# ── Lead enrollment ───────────────────────────────────────────────────────────

def add_lead_to_campaign(
    lead: dict,
    campaign_id,
    list_id=None,
    first_message: str = "",
) -> bool:
    """Add a lead to a HeyReach campaign via AddLeadsToCampaignV2.

    The composed personalization is passed as the custom field "message";
    configure the campaign's first step to use {{message}}. campaign_id and the
    sender account id must be numeric. Returns True on success.
    """
    hr = _config()["heyreach"]
    sender_id = hr.get("sender_linkedin_account_id")

    custom_fields = [
        {"name": "message",    "value": first_message},
        {"name": "influencer", "value": lead.get("source_influencer", "")},
        {"name": "angle",      "value": lead.get("scoring", {}).get("angle", "")},
    ]

    payload = {
        "campaignId": campaign_id,
        "accountLeadPairs": [
            {
                "linkedInAccountId": sender_id,
                "lead": {
                    "firstName":        lead.get("firstName", ""),
                    "lastName":         lead.get("lastName", ""),
                    "profileUrl":       lead.get("profileUrl", ""),
                    "companyName":      lead.get("company", ""),
                    "position":         lead.get("headline", ""),
                    "customUserFields": custom_fields,
                },
            }
        ],
    }
    try:
        _r("POST", "/campaign/AddLeadsToCampaignV2", json=payload)
        return True
    except requests.HTTPError as exc:
        print(f"[heyreach] enroll failed for {lead.get('profileUrl')}: {exc}")
        return False


# ── Inbox ─────────────────────────────────────────────────────────────────────

def get_inbox_messages(since_hours: int = 2) -> list:
    """Fetch recent conversations/messages via GetConversationsV2.

    Returns a list of normalized message dicts:
        messageId, conversationId, leadId, profileUrl, firstName, lastName,
        company, text, receivedAt
    """
    since_iso = (datetime.datetime.utcnow() - datetime.timedelta(hours=since_hours)).strftime(
        "%Y-%m-%dT%H:%M:%SZ"
    )
    payload = {"offset": 0, "limit": 100, "filters": {"newMessagesAfter": since_iso}}
    try:
        data = _r("POST", "/inbox/GetConversationsV2", json=payload)
    except requests.HTTPError as exc:
        print(f"[heyreach] inbox fetch failed: {exc}")
        return []

    conversations = data.get("items", data) if isinstance(data, dict) else data
    messages = []
    for conv in conversations or []:
        corr = conv.get("correspondentProfile", {}) or {}
        last = conv.get("lastMessage", {}) or {}
        messages.append(
            {
                "messageId":      last.get("id", conv.get("id", "")),
                "conversationId": conv.get("id", ""),
                "leadId":         corr.get("id", ""),
                "profileUrl":     corr.get("profileUrl", ""),
                "firstName":      corr.get("firstName", ""),
                "lastName":       corr.get("lastName", ""),
                "company":        corr.get("companyName", ""),
                "text":           last.get("body", last.get("text", "")),
                "receivedAt":     last.get("createdAt", ""),
            }
        )
    return messages


def reply_to_message(conversation_id, body: str) -> bool:
    """Send a reply into an existing conversation. Returns True on success."""
    payload = {"conversationId": conversation_id, "message": body}
    try:
        _r("POST", "/inbox/SendMessage", json=payload)
        return True
    except requests.HTTPError as exc:
        print(f"[heyreach] reply failed for conversation {conversation_id}: {exc}")
        return False


def stop_sequence(profile_url: str, campaign_id=None) -> bool:
    """Stop a lead in a campaign (opt-out). Returns True on success."""
    hr = _config()["heyreach"]
    if campaign_id is None:
        campaign_id = hr["campaign_id_tier_a"]
    payload = {"campaignId": campaign_id, "leadProfileUrl": profile_url}
    try:
        _r("POST", "/campaign/StopLeadInCampaign", json=payload)
        return True
    except requests.HTTPError as exc:
        print(f"[heyreach] stop_sequence failed for {profile_url}: {exc}")
        return False
