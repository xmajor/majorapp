# Daily Runbook — Stages 1–4

Run this every day (cron, CI, or `/run-daily` in Claude Code).
Stages must run **in order**; each stage's output feeds the next.

---

## Pre-flight checklist

```python
import json, pathlib, datetime

cfg   = json.loads(pathlib.Path("config/pipeline.json").read_text())
today = datetime.date.today().isoformat()
print(f"Run date: {today}")
print(f"HeyReach campaign A: {cfg['heyreach']['campaign_id_tier_a']}")
print(f"HeyReach campaign B: {cfg['heyreach']['campaign_id_tier_b']}")
print(f"Booking link: {cfg['booking']['link']}")
```

Abort if campaign IDs or booking link are still placeholders.

---

## Stage 1 — Monitor Influencers

Follow `prompts/01_monitor_influencers.md`.

**Goal**: Collect all posts published by the 20 influencers in the last
`pipeline.json > apify.days_back` days.

**Output**: Save to `state/posts_YYYY-MM-DD.json`.

---

## Stage 2 — Extract Engagers

Follow `prompts/02_extract_engagers.md`.

**Input**: `state/posts_YYYY-MM-DD.json` from stage 1.

**Goal**: For each post, collect all likers and commenters. Dedupe across posts
so each person appears once. Strip anyone already in suppression or contacted.

**Output**: Save net-new engagers to `state/engagers_YYYY-MM-DD.json`.

---

## Stage 3 — Research + Score

Follow `prompts/03_research_and_score.md`.

**Input**: `state/engagers_YYYY-MM-DD.json` from stage 2.

**Goal**: For each engager, run web research, identify observable signals, call
`scripts/score.py`, and log every lead to `state/scored.jsonl`.

**Output**: Tier A leads → `state/tier_a_YYYY-MM-DD.json`.
           Tier B leads → `state/tier_b_YYYY-MM-DD.json`.

---

## Stage 4 — Push to HeyReach

Follow `prompts/04_push_to_heyreach.md`.

**Input**: `state/tier_a_YYYY-MM-DD.json` and `state/tier_b_YYYY-MM-DD.json`.

**Goal**: Enroll each qualified lead in the correct HeyReach campaign with a
personalized first message. Respect daily caps. Mark each enrolled lead in
`state/contacted.json`.

**Output**: Enrollment confirmations logged to `state/audit_log.jsonl`.

---

## Run summary (print at end)

```
=== SalesKick Daily Run — {date} ===
Posts fetched:        {n}
Net-new engagers:     {n}
Scored — Tier A:      {n}
Scored — Tier B:      {n}
Scored — No contact:  {n}
Pushed to HeyReach:   {n}  (A: {n}, B: {n})
Skipped (cap/dup):    {n}
Escalations flagged:  {n}
=====================================
```
