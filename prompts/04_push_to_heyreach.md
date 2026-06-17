# Stage 4 — Push Qualified Leads to HeyReach

## Goal
Enroll Tier A and Tier B leads in the correct HeyReach campaigns with personalized
first messages. Respect daily caps. Mark every enrolled lead as contacted.

## Steps

### 1. Load config and today's scored leads
```python
import json, pathlib, datetime
today   = datetime.date.today().isoformat()
cfg     = json.loads(pathlib.Path("config/pipeline.json").read_text())
tier_a  = json.loads(pathlib.Path(f"state/tier_a_{today}.json").read_text())
tier_b  = json.loads(pathlib.Path(f"state/tier_b_{today}.json").read_text())
```

### 2. Check today's HeyReach usage against daily caps
```python
from scripts.state import count_contacted_today

already_a = count_contacted_today("A")
already_b = count_contacted_today("B")
cap_a     = cfg["heyreach"]["daily_cap_tier_a"]
cap_b     = cfg["heyreach"]["daily_cap_tier_b"]

remaining_a = max(0, cap_a - already_a)
remaining_b = max(0, cap_b - already_b)
print(f"Remaining capacity — Tier A: {remaining_a}, Tier B: {remaining_b}")

tier_a = tier_a[:remaining_a]
tier_b = tier_b[:remaining_b]
```

### 3. Build personalized first messages
For each lead, select the message template from `templates/messages.md` matching
the angle returned by `score.py`. Fill all `{{PLACEHOLDER}}` fields.

```python
import re

def fill_template(template: str, lead: dict) -> str:
    scoring   = lead.get("scoring", {})
    angle     = scoring.get("angle", "generic_credibility")
    
    # Load angle hook from scoring config
    scoring_cfg = json.loads(pathlib.Path("config/lead_scoring.json").read_text())
    angle_data  = scoring_cfg["angles"].get(angle, scoring_cfg["angles"]["generic_credibility"])
    
    return (
        template
        .replace("{{FIRST_NAME}}",        lead.get("firstName", "there"))
        .replace("{{COMPANY}}",           lead.get("company", "your company"))
        .replace("{{INFLUENCER_NAME}}",   lead.get("source_influencer", ""))
        .replace("{{HOOK}}",              angle_data["hook"])
        .replace("{{OFFER}}",             angle_data["offer"])
        .replace("{{BOOKING_LINK}}",      cfg["booking"]["link"])
    )
```

Load the correct template from `templates/messages.md` for the lead's tier and angle.

### 4. Enroll leads in HeyReach
```python
from scripts.heyreach import add_lead_to_campaign
from scripts.state   import mark_contacted, append_audit

enrolled = 0
skipped  = 0

for tier_label, leads, campaign_id in [
    ("A", tier_a, cfg["heyreach"]["campaign_id_tier_a"]),
    ("B", tier_b, cfg["heyreach"]["campaign_id_tier_b"]),
]:
    list_id = cfg["heyreach"]["list_id"]
    
    for lead in leads:
        # Final suppression check (belt-and-suspenders)
        from scripts.state import is_suppressed, is_contacted
        if is_suppressed(lead["profileUrl"]) or is_contacted(lead["profileUrl"]):
            skipped += 1
            continue
        
        first_msg = fill_template(TEMPLATE_TEXT, lead)
        
        success = add_lead_to_campaign(
            lead       = lead,
            campaign_id= campaign_id,
            list_id    = list_id,
            first_message = first_msg,
        )
        
        if success:
            mark_contacted(lead)
            append_audit({
                "event":       "enrolled",
                "profile_url": lead["profileUrl"],
                "tier":        tier_label,
                "campaign_id": campaign_id,
                "angle":       lead["scoring"]["angle"],
                "date":        today,
            })
            enrolled += 1
        else:
            append_audit({
                "event":       "enroll_failed",
                "profile_url": lead["profileUrl"],
                "tier":        tier_label,
                "date":        today,
            })
            skipped += 1

print(f"Enrolled: {enrolled}, Skipped/failed: {skipped}")
```

## Personalization requirements

### Tier A — required
Every Tier A message MUST include:
1. The influencer's name and a reference to the specific post they engaged with.
2. The angle hook line tailored to the strongest matching trigger signal.
3. The free-training offer and booking link.

### Tier B — preferred
Tier B messages should reference the influencer/niche. Generic fallback is acceptable
only when no strong trigger signal fired and confidence is low.

### Never include
- "Reply STOP to unsubscribe" — HeyReach handles compliance footer.
- Fabricated social proof (fake customer names, made-up results).
- Pricing, contract terms, or commitment language.

## HeyReach field mapping
When calling `add_lead_to_campaign`, pass these fields from the lead dict:

| HeyReach field | Source |
|----------------|--------|
| `firstName`    | `lead["firstName"]` |
| `lastName`     | `lead["lastName"]` |
| `linkedInUrl`  | `lead["profileUrl"]` |
| `companyName`  | `lead["company"]` |
| `jobTitle`     | `lead["headline"]` |
| `customVar1`   | `lead["source_influencer"]` |
| `customVar2`   | `lead["scoring"]["angle"]` |
| `firstMessage` | personalized message from step 3 |

## Notes
- If HeyReach MCP is connected, use it directly instead of `scripts/heyreach.py` —
  same field mapping applies.
- On API error for a specific lead, log to audit and continue; don't abort the batch.
- Do NOT re-run this stage on the same day — it would double-enroll. Check
  `state/last_run.json` before starting.
