#!/usr/bin/env python3
"""Offline dry-run: score leads and preview the exact DM + HeyReach payload the
pipeline would send — without any network calls (no Apify, no HeyReach).

Usage:
    python3 scripts/dryrun.py                      # uses a built-in synthetic sample
    python3 scripts/dryrun.py state/engagers_X.json  # previews a real engagers file

Nothing is sent. This validates scoring, angle selection, personalization, and
the HeyReach request shape so the live run behaves predictably once egress to
api.apify.com / api.heyreach.io is allowed.
"""

import sys
import json
import pathlib

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent.parent))
from scripts.score import score_lead

CFG     = json.loads(pathlib.Path("config/pipeline.json").read_text())
SCORING = json.loads(pathlib.Path("config/lead_scoring.json").read_text())

# Faithful to prompts/04_push_to_heyreach.md: greeting + HOOK + OFFER.
SKELETON = "Hey {first} — saw you engaging with {influencer}'s post.\n\n{hook}\n\n{offer}"


def build_dm(lead: dict) -> str:
    angle_key  = lead["scoring"]["angle"]
    angle      = SCORING["angles"].get(angle_key, SCORING["angles"]["generic_credibility"])
    return SKELETON.format(
        first=lead.get("firstName", "there"),
        influencer=lead.get("source_influencer", "them"),
        hook=angle["hook"],
        offer=angle["offer"],
    )


def heyreach_payload(lead: dict, dm: str) -> dict:
    hr   = CFG["heyreach"]
    tier = lead["scoring"]["tier"]
    campaign_id = hr["campaign_id_tier_a"] if tier == "A" else hr["campaign_id_tier_b"]
    return {
        "_endpoint": "POST /campaign/AddLeadsToCampaignV2",
        "campaignId": campaign_id,
        "accountLeadPairs": [
            {
                "linkedInAccountId": hr["sender_linkedin_account_id"],
                "lead": {
                    "firstName":  lead.get("firstName", ""),
                    "lastName":   lead.get("lastName", ""),
                    "profileUrl": lead.get("profileUrl", ""),
                    "companyName": lead.get("company", ""),
                    "position":   lead.get("headline", ""),
                    "customUserFields": [
                        {"name": "message",    "value": dm},
                        {"name": "influencer", "value": lead.get("source_influencer", "")},
                        {"name": "angle",      "value": lead["scoring"]["angle"]},
                    ],
                },
            }
        ],
    }


SYNTHETIC = [
    {
        "firstName": "Jordan", "lastName": "Example",
        "profileUrl": "https://www.linkedin.com/in/jordan-example-SAMPLE",
        "company": "Apex Coaching Co", "headline": "Founder & CEO at Apex Coaching Co",
        "industry": "Professional Training & Coaching",
        "about": "We run a $12k mastermind. Our setters book strategy calls from paid ads for our closers.",
        "source_influencer": "Alex Hormozi",
        "source_post_text": "Our show rate on booked calls cratered this month and it's killing revenue.",
        "engagement_type": "commented",
        "signal_post_about_show_rate": True,
        "signal_complained_about_noshows": True,
        "signal_runs_paid_traffic_to_calls": True,
        "confidence_role_fit": "high", "confidence_business_type_fit": "high",
    },
    {
        "firstName": "Sam", "lastName": "Sample",
        "profileUrl": "https://www.linkedin.com/in/sam-sample-SAMPLE",
        "company": "Sample Agency", "headline": "Business Coach",
        "industry": "Coaching", "about": "I sell a coaching program.",
        "source_influencer": "Russell Brunson",
        "engagement_type": "commented",
        "signal_high_ticket_offer": True, "signal_post_about_closing_or_setters": True,
    },
    {
        "firstName": "Pat", "lastName": "Placeholder",
        "profileUrl": "https://www.linkedin.com/in/pat-placeholder-SAMPLE",
        "headline": "Marketing Student | Open to work", "engagement_type": "liked",
    },
]


def main():
    if len(sys.argv) > 1:
        leads = json.loads(pathlib.Path(sys.argv[1]).read_text())
        print(f"Previewing {len(leads)} leads from {sys.argv[1]}\n")
    else:
        leads = SYNTHETIC
        print("Previewing built-in SYNTHETIC sample (no real contacts)\n")

    counts = {"A": 0, "B": 0, "skip": 0}
    for lead in leads:
        result = score_lead(lead)
        lead["scoring"] = result
        name = f"{lead.get('firstName','?')} {lead.get('lastName','')}".strip()

        if result["tier"] in ("A", "B"):
            counts[result["tier"]] += 1
            dm = build_dm(lead)
            print("=" * 70)
            print(f"{name}  →  TIER {result['tier']}  (total {result['total']}/30, angle: {result['angle']})")
            print("-" * 70)
            print("DM that would be sent:\n")
            print(dm)
            print("\nHeyReach payload:")
            print(json.dumps(heyreach_payload(lead, dm), indent=2))
            print()
        else:
            counts["skip"] += 1
            print("=" * 70)
            print(f"{name}  →  SKIP  (gate: {result['gate_result']}, total {result['total']})")
            print()

    print("=" * 70)
    print(f"Summary: Tier A {counts['A']}, Tier B {counts['B']}, skipped {counts['skip']}")
    print("NOTE: dry run only — nothing was scraped or sent.")


if __name__ == "__main__":
    main()
