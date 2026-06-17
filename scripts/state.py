#!/usr/bin/env python3
"""State management — suppression, contacted list, audit logs, and scored/meeting records."""

import json
import pathlib
import datetime

_CFG_PATH = pathlib.Path("config/pipeline.json")
_cfg = None


def _config() -> dict:
    global _cfg
    if _cfg is None:
        _cfg = json.loads(_CFG_PATH.read_text())
    return _cfg


def _normalize_url(url: str) -> str:
    return url.strip().rstrip("/").lower()


# ── Suppression ───────────────────────────────────────────────────────────────

def _load_suppression() -> set:
    path = pathlib.Path(_config()["state"]["suppression_file"])
    if not path.exists():
        return set()
    data = json.loads(path.read_text())
    return {_normalize_url(u) for u in data.get("urls", [])}


def is_suppressed(linkedin_url: str) -> bool:
    return _normalize_url(linkedin_url) in _load_suppression()


def suppress(linkedin_url: str) -> None:
    path = pathlib.Path(_config()["state"]["suppression_file"])
    data = json.loads(path.read_text()) if path.exists() else {"urls": []}
    norm = _normalize_url(linkedin_url)
    if norm not in {_normalize_url(u) for u in data["urls"]}:
        data["urls"].append(norm)
        path.write_text(json.dumps(data, indent=2))


# ── Contacted ─────────────────────────────────────────────────────────────────

def _load_contacted() -> dict:
    path = pathlib.Path(_config()["state"]["contacted_file"])
    if not path.exists():
        return {}
    return json.loads(path.read_text())


def is_contacted(linkedin_url: str) -> bool:
    return _normalize_url(linkedin_url) in _load_contacted()


def mark_contacted(lead: dict) -> None:
    path = pathlib.Path(_config()["state"]["contacted_file"])
    data = _load_contacted()
    norm = _normalize_url(lead["profileUrl"])
    data[norm] = {
        "first_name":    lead.get("firstName", ""),
        "last_name":     lead.get("lastName", ""),
        "company":       lead.get("company", ""),
        "tier":          lead.get("scoring", {}).get("tier", ""),
        "contacted_at":  datetime.datetime.utcnow().isoformat(),
        "follow_up_date": None,
    }
    path.write_text(json.dumps(data, indent=2))


def count_contacted_today(tier: str) -> int:
    today = datetime.date.today().isoformat()
    data  = _load_contacted()
    return sum(
        1 for v in data.values()
        if v.get("tier") == tier and (v.get("contacted_at") or "").startswith(today)
    )


# ── Audit log ─────────────────────────────────────────────────────────────────

def append_audit(record: dict) -> None:
    path = pathlib.Path(_config()["state"]["audit_log_file"])
    path.parent.mkdir(parents=True, exist_ok=True)
    record.setdefault("_ts", datetime.datetime.utcnow().isoformat())
    with path.open("a") as f:
        f.write(json.dumps(record) + "\n")


# ── Scored log ────────────────────────────────────────────────────────────────

def append_scored(lead: dict) -> None:
    path = pathlib.Path(_config()["state"]["scored_log_file"])
    path.parent.mkdir(parents=True, exist_ok=True)
    record = {
        "profile_url": lead.get("profileUrl", ""),
        "name":        f"{lead.get('firstName','')} {lead.get('lastName','')}".strip(),
        "company":     lead.get("company", ""),
        "scoring":     lead.get("scoring", {}),
        "_ts":         datetime.datetime.utcnow().isoformat(),
    }
    with path.open("a") as f:
        f.write(json.dumps(record) + "\n")


# ── Meetings ──────────────────────────────────────────────────────────────────

def append_meeting(record: dict) -> None:
    path = pathlib.Path(_config()["state"]["meetings_file"])
    path.parent.mkdir(parents=True, exist_ok=True)
    record.setdefault("_ts", datetime.datetime.utcnow().isoformat())
    with path.open("a") as f:
        f.write(json.dumps(record) + "\n")


# ── Escalations ───────────────────────────────────────────────────────────────

def append_escalation(record: dict) -> None:
    path = pathlib.Path(_config()["state"]["escalations_file"])
    path.parent.mkdir(parents=True, exist_ok=True)
    record.setdefault("_ts", datetime.datetime.utcnow().isoformat())
    with path.open("a") as f:
        f.write(json.dumps(record) + "\n")


# ── Referrals ─────────────────────────────────────────────────────────────────

def append_referral(record: dict) -> None:
    path = pathlib.Path(_config()["state"]["referrals_file"])
    path.parent.mkdir(parents=True, exist_ok=True)
    record.setdefault("_ts", datetime.datetime.utcnow().isoformat())
    with path.open("a") as f:
        f.write(json.dumps(record) + "\n")


# ── Last-run timestamps ───────────────────────────────────────────────────────

def set_last_run(stage: str) -> None:
    path = pathlib.Path(_config()["state"]["last_run_file"])
    data = json.loads(path.read_text()) if path.exists() else {}
    data[stage] = datetime.datetime.utcnow().isoformat()
    path.write_text(json.dumps(data, indent=2))


def get_last_run(stage: str) -> str | None:
    path = pathlib.Path(_config()["state"]["last_run_file"])
    if not path.exists():
        return None
    return json.loads(path.read_text()).get(stage)
