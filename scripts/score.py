#!/usr/bin/env python3
"""Deterministic ICP scoring — applies config/lead_scoring.json to a lead dict.

Call score_lead(lead) and use its output verbatim. Do not override scores.
"""

import json
import pathlib

_model = None


def _scoring_model() -> dict:
    global _model
    if _model is None:
        _model = json.loads(pathlib.Path("config/lead_scoring.json").read_text())
    return _model


def _normalize(text: str) -> str:
    return text.lower().strip()


def _matches_any(haystack: str, needles: list) -> bool:
    h = _normalize(haystack)
    return any(_normalize(n) in h for n in needles)


# ── Gates ─────────────────────────────────────────────────────────────────────

def _check_gates(lead: dict, gates: dict) -> tuple[bool, str]:
    """Return (passed, reason). If not passed, reason explains which gate failed."""
    title    = lead.get("headline", "") or lead.get("title", "") or ""
    industry = lead.get("industry", "") or ""
    size     = lead.get("employeeCount", 0) or lead.get("company_employee_count", 0) or 0

    if not _matches_any(title, gates["title_keywords"]):
        return False, "title_gate_fail"

    if _matches_any(title, gates["excluded_title_keywords"]):
        return False, "title_excluded"

    if not (gates["min_employees"] <= int(size) <= gates["max_employees"]):
        return False, f"size_gate_fail (got {size})"

    if not _matches_any(industry, gates["allowed_industries"]):
        return False, "industry_gate_fail"

    if _matches_any(industry, gates["excluded_industries"]):
        return False, "industry_excluded"

    return True, "passed"


# ── Fit dimensions ────────────────────────────────────────────────────────────

def _score_dimension(lead: dict, dim_name: str, dim_cfg: dict) -> tuple[int, str, str]:
    """Return (points, matched_label, confidence)."""
    title    = lead.get("headline", "") or lead.get("title", "") or ""
    industry = lead.get("industry", "") or ""
    size     = int(lead.get("employeeCount", 0) or lead.get("company_employee_count", 0) or 0)
    tech     = lead.get("tech_stack", "") or ""
    funding  = lead.get("funding_stage", "") or ""
    eng_type = lead.get("engagement_type", "") or ""

    confidence_key = f"confidence_{dim_name}"
    confidence = lead.get(confidence_key, "medium")

    for rule in dim_cfg["rules"]:
        matched = False

        if "match_any" in rule:
            if dim_name == "title_seniority":
                matched = _matches_any(title, rule["match_any"])
            elif dim_name == "tech_stack":
                matched = _matches_any(tech, rule["match_any"]) or _matches_any(title, rule["match_any"])
            elif dim_name == "funding_stage":
                matched = _matches_any(funding, rule["match_any"])
            elif dim_name == "icp_engagement_quality":
                matched = _matches_any(eng_type, rule["match_any"])
            else:
                search_space = f"{title} {industry} {tech} {funding}"
                matched = _matches_any(search_space, rule["match_any"])

        elif "range" in rule:
            lo, hi = rule["range"]
            matched = lo <= size <= hi

        if matched:
            return rule["points"], rule["label"], confidence

    return 0, "no_match", confidence


def _score_fit(lead: dict, dims: dict) -> tuple[int, list]:
    total = 0
    signals = []
    for dim_name, dim_cfg in dims.items():
        if dim_name.startswith("_"):
            continue
        points, label, confidence = _score_dimension(lead, dim_name, dim_cfg)
        capped = min(points, dim_cfg["max_points"])
        total += capped
        if capped > 0:
            signals.append({
                "dimension": dim_name,
                "label":     label,
                "points":    capped,
                "confidence": confidence,
            })
    return total, signals


# ── Triggers ──────────────────────────────────────────────────────────────────

def _score_triggers(lead: dict, triggers_cfg: dict) -> tuple[int, list]:
    total = 0
    fired = []
    max_bonus = triggers_cfg["max_total_bonus"]

    for item in triggers_cfg["items"]:
        if lead.get(item["id"]):
            bonus = item["bonus"]
            total += bonus
            fired.append(item["id"])

    return min(total, max_bonus), fired


# ── Angle selection ───────────────────────────────────────────────────────────

def _pick_angle(triggers_fired: list, angles: dict) -> str:
    best_angle = "generic_credibility"
    best_overlap = 0

    for angle_name, angle_data in angles.items():
        sigs = angle_data.get("trigger_signals", [])
        overlap = sum(1 for s in sigs if s in triggers_fired)
        if overlap > best_overlap:
            best_overlap = overlap
            best_angle = angle_name

    return best_angle


# ── Confidence cap ────────────────────────────────────────────────────────────

def _count_low_confidence_dims(lead: dict, dims: dict) -> int:
    count = 0
    for dim_name in dims:
        if dim_name.startswith("_"):
            continue
        if lead.get(f"confidence_{dim_name}", "medium") == "low":
            count += 1
    return count


# ── Public API ────────────────────────────────────────────────────────────────

def score_lead(lead: dict) -> dict:
    """Apply the ICP scoring model to a lead dict.

    Expected lead fields (all optional — missing = scored as zero/low):
        headline / title         str   current job title
        industry                 str   company industry
        employeeCount            int   company headcount
        tech_stack               str   known tools (space-separated)
        funding_stage            str   e.g. "series b"
        engagement_type          str   "commented" | "liked"
        confidence_<dim>         str   "high" | "medium" | "low"
        signal_<trigger_id>      bool  True if signal is observed

    Returns:
        fit          int    raw fit score
        trigger      int    trigger bonus
        total        int    fit + trigger
        tier         str    "A" | "B" | None
        angle        str    angle key from lead_scoring.json
        signals      list   matched fit signals with points + confidence
        triggers     list   fired trigger IDs
        gate_result  str    "passed" or failure reason
        confidence_capped  bool  True if tier was capped due to low-confidence dims
    """
    model = _scoring_model()

    gate_passed, gate_reason = _check_gates(lead, model["gates"])
    if not gate_passed:
        return {
            "fit":               0,
            "trigger":           0,
            "total":             0,
            "tier":              None,
            "angle":             None,
            "signals":           [],
            "triggers":          [],
            "gate_result":       gate_reason,
            "confidence_capped": False,
        }

    fit_score, signals   = _score_fit(lead, model["fit_dimensions"])
    trigger_score, fired = _score_triggers(lead, model["triggers"])
    total                = fit_score + trigger_score
    thresholds           = model["scoring"]["tier_thresholds"]

    if total >= thresholds["tier_a"]:
        tier = "A"
    elif total >= thresholds["tier_b_min"]:
        tier = "B"
    else:
        tier = None

    angle = _pick_angle(fired, model["angles"]) if tier else None

    low_count       = _count_low_confidence_dims(lead, model["fit_dimensions"])
    confidence_rule = model["scoring"]["confidence_cap_rule"]
    capped          = False
    if tier == "A" and low_count >= 2:
        tier   = "B"
        capped = True

    return {
        "fit":               fit_score,
        "trigger":           trigger_score,
        "total":             total,
        "tier":              tier,
        "angle":             angle,
        "signals":           signals,
        "triggers":          fired,
        "gate_result":       "passed",
        "confidence_capped": capped,
    }


if __name__ == "__main__":
    import sys

    sample = {
        "headline": "VP of Sales",
        "industry": "SaaS",
        "employeeCount": 120,
        "tech_stack": "Salesforce Gong",
        "funding_stage": "series b",
        "engagement_type": "commented",
        "signal_company_recently_funded": True,
        "signal_company_hiring_sales_reps": True,
        "confidence_title_seniority": "high",
        "confidence_company_size": "high",
    }
    result = score_lead(sample)
    print(json.dumps(result, indent=2))
