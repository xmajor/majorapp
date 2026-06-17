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
| Company funding stage | `"{company}" site:techcrunch.com OR crunchbase.com funding` |
| Company employee count | LinkedIn company page or Crunchbase |
| Open sales roles | `site:linkedin.com/jobs "{company}" "account executive" OR "SDR"` |
| Tech stack | `"{company}" uses Salesforce OR HubSpot OR Salesloft` |
| Recent leadership change | `"{first} {last}" "joins" OR "appointed" "{company}" sales` |

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
    #   lead["signal_company_hiring_sales_reps"]  = True  # saw open AE role
    #   lead["signal_company_recently_funded"]    = True  # found Crunchbase round
    #   lead["signal_post_about_ramp_time"]       = True  # source post was about ramp
    #   lead["confidence_company_size"]           = "high"  # from LinkedIn company page
    #   lead["confidence_tech_stack"]             = "low"   # no data found

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
| `signal_post_about_sales_training` | Source post topic is sales training / coaching |
| `signal_post_about_quota_miss` | Source post mentions quota, attainment, miss |
| `signal_post_about_ramp_time` | Source post mentions onboarding, ramp, new reps |
| `signal_engaged_with_sales_training_content` | Lead commented (not just liked) on training post |
| `signal_company_recently_funded` | Crunchbase/TechCrunch round in last 90 days |
| `signal_company_hiring_sales_reps` | Open AE/SDR LinkedIn job posting |
| `signal_rep_turnover_signal` | Multiple recent AE postings or "building team" language |
| `signal_recent_leadership_change` | Lead started role < 6 months ago |
| `signal_competitor_user` | Company uses a competing sales training product |

Set each as `True` / `False` on the lead dict. Omit (or set `False`) if no evidence.

## Notes
- Never fabricate signals. If you cannot find data, leave the signal `False` and mark
  the dimension confidence `"low"`.
- The scoring model uses `signal_*` keys verbatim — spelling must match exactly.
- Aim to process all engagers; if research takes too long on a batch, score remaining
  leads with profile-only data and mark relevant dimensions `"low"` confidence.
