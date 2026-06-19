# Stage 3 — Research + Score

## Goal
For each net-new engager, gather enough public data to fire the scoring model, then call
`scripts/score.py` to get a deterministic tier. Log every lead to `state/scored.jsonl`.

## Steps

### 1. Load today's engagers
```python
import json, pathlib, datetime
today    = datetime.date.today().isoformat()
engagers = json.loads(pathlib.Path(f"state/engagers_{today}.json").read_text())
print(f"Engagers to score: {len(engagers)}")
```

### 2. For each engager — enrich profile data
Use Apify's LinkedIn profile scraper to get structured data:

```python
from scripts.apify import get_profile_details
profile_urls = [e["profileUrl"] for e in engagers]

# Batch in groups of 50 to manage Apify cost
BATCH = 50
profiles = []
for i in range(0, len(profile_urls), BATCH):
    batch = profile_urls[i:i+BATCH]
    profiles.extend(get_profile_details(batch))

# Index by profileUrl
profile_map = {p.get("profileUrl", "").strip().rstrip("/"): p for p in profiles}
```

### 3. For each engager — web research (targeted)
Use `web_search` / `web_fetch` to fill gaps in profile data when the Apify scrape
returns thin results. Focus on these high-value signals:

| Signal to verify | Search query pattern |
|-----------------|----------------------|
| High-ticket offer | `"{first} {last}" mastermind OR "high ticket" OR "$" program` |
| Runs paid traffic to calls | `"{company}" book a call OR strategy call OR application funnel` |
| Hiring closers/setters | `"{company}" hiring "closer" OR "appointment setter" OR "commission"` |
| Sales team maturity | profile/about text mentioning setters, closers, sales team |
| Recent launch | `"{first} {last}" launched OR "new program" OR cohort` |

Only search for leads where profile data is incomplete. Cap research at 2 searches
per lead to control cost and latency.

### 4. Identify observable signals and call score.py
Map what you found to the signal IDs in `config/lead_scoring.json > triggers.items`.

```python
from scripts.score import score_lead

tier_a, tier_b, no_contact = [], [], []

for eng in engagers:
    url     = eng["profileUrl"].strip().rstrip("/")
    profile = profile_map.get(url, {})

    # Merge engager + profile data
    lead = {**eng, **profile}

    # Your judgment: set signal booleans based on research
    # Examples:
    #   lead["signal_post_about_show_rate"]        = True  # source post was about no-shows
    #   lead["signal_complained_about_noshows"]    = True  # lead complained about cancellations
    #   lead["signal_hiring_closers_or_setters"]   = True  # saw a "hiring closers" post
    #   lead["signal_runs_paid_traffic_to_calls"]  = True  # ad → booking calendar funnel
    #   lead["signal_high_ticket_offer"]           = True  # $15k mastermind on their site
    #   lead["confidence_role_fit"]                = "high"  # title clear on profile
    #   lead["confidence_high_ticket_signal"]      = "low"   # no offer data found

    result = score_lead(lead)
    lead["scoring"] = result

    from scripts.state import append_scored
    append_scored(lead)

    if result["tier"] == "A":
        tier_a.append(lead)
    elif result["tier"] == "B":
        tier_b.append(lead)
    else:
        no_contact.append(lead)

print(f"Tier A: {len(tier_a)}, Tier B: {len(tier_b)}, No contact: {len(no_contact)}")
```

### 5. Confidence cap
If a lead has 2 or more dimensions marked `"low"` confidence, downgrade tier A → B
and add `"confidence_capped": true` to their scoring dict. Flag these leads in
`state/escalations.jsonl` for human review.

```python
from scripts.state import append_escalation

final_tier_a = []
for lead in tier_a:
    low_dims = sum(
        1 for k, v in lead.items()
        if k.startswith("confidence_") and v == "low"
    )
    if low_dims >= 2:
        lead["scoring"]["confidence_capped"] = True
        lead["scoring"]["tier"] = "B"
        tier_b.append(lead)
        append_escalation({
            "reason": "confidence_cap",
            "lead_url": lead["profileUrl"],
            "low_dims": low_dims,
            "date": today,
        })
    else:
        final_tier_a.append(lead)

tier_a = final_tier_a
```

### 6. Save scored tiers
```python
pathlib.Path(f"state/tier_a_{today}.json").write_text(json.dumps(tier_a, indent=2))
pathlib.Path(f"state/tier_b_{today}.json").write_text(json.dumps(tier_b, indent=2))
print(f"Saved tier_a_{today}.json ({len(tier_a)}) and tier_b_{today}.json ({len(tier_b)}).")
```

## Signal identification guide

When reading a lead's profile + posts, look for these observable proxies:

| Signal ID | Look for |
|-----------|----------|
| `signal_post_about_show_rate` | Source post is about show rate, no-shows, booked calls not showing |
| `signal_complained_about_noshows` | Lead complains about no-shows, cancellations, ghosted/cold calls |
| `signal_hiring_closers_or_setters` | Hiring closers, appointment setters, or commission reps |
| `signal_runs_paid_traffic_to_calls` | Runs ads to a booking calendar / application funnel |
| `signal_post_about_closing_or_setters` | Source post about closing, setters, or call conversion |
| `signal_high_ticket_offer` | Mastermind / $3k+ program / done-for-you retainer sold via calls |
| `signal_scaling_sales_team` | "Building / scaling a sales team" language |
| `signal_large_audience` | Large following / high inbound call volume |
| `signal_recent_launch` | Recently launched a program, offer, or cohort |

Set each as `True` / `False` on the lead dict. Omit (or set `False`) if no evidence.

## Notes
- Never fabricate signals. If you cannot find data, leave the signal `False` and mark
  the dimension confidence `"low"`.
- The scoring model uses `signal_*` keys verbatim — spelling must match exactly.
- Aim to process all engagers; if research takes too long on a batch, score remaining
  leads with profile-only data and mark relevant dimensions `"low"` confidence.
