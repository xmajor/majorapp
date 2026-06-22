# LinkedIn Engagement Outbound

Pulls the people who engaged with a LinkedIn post (via an [Apify](https://apify.com)
actor) and pushes them into a [HeyReach](https://heyreach.io) list as leads, so
they can be enrolled in an outreach campaign.

## Flow

```
LinkedIn post URL
      │
      ▼
Apify actor (reactions/comments scraper)  ──►  raw engagement records
      │
      ▼
EngagementOutbound  ──►  normalized HeyReach leads (deduped by profile URL)
      │
      ▼
HeyReach list  ──►  campaign / outreach
```

## Components

- `apify_client.rb` — runs an Apify actor synchronously and returns dataset items.
- `heyreach_client.rb` — adds leads to a HeyReach list (`/list/AddLeadsToListV2`).
- `engagement_outbound.rb` — orchestrates scrape → normalize → push.
- `../tasks/linkedin_outbound.rake` — the `linkedin_outbound:run` entry point.

## Setup

1. `cp .env.example .env` and fill in your keys + target. `.env` is gitignored —
   **never commit real credentials.**
2. Export the vars (e.g. `set -a; source .env; set +a`) or pass them inline.

## Running

Dry run (scrape + map, no push — safe to test):

```sh
DRY_RUN=1 \
APIFY_TOKEN=... \
APIFY_ACTOR=apify~linkedin-post-reactions-scraper \
POST_URL="https://www.linkedin.com/posts/..." \
bundle exec rake linkedin_outbound:run
```

Full run (pushes to HeyReach):

```sh
APIFY_TOKEN=... HEYREACH_API_KEY=... \
APIFY_ACTOR=apify~linkedin-post-reactions-scraper \
POST_URL="https://www.linkedin.com/posts/..." \
HEYREACH_LIST_ID=12345 \
bundle exec rake linkedin_outbound:run
```

## Notes

- Different Apify actors emit different field names. The mapper probes common
  keys (`profileUrl`, `linkedinUrl`, `fullName`, `firstName`, etc.); a record is
  only kept if a LinkedIn profile URL is found. Tune `to_heyreach_lead` if your
  actor uses other field names.
- Leads are deduped by normalized profile URL before pushing.
- This sends real outreach. Confirm the post URL, actor, and list id before a
  full run.
