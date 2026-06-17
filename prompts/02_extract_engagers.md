# Stage 2 — Extract Engagers

## Goal
For every post from stage 1, collect all likers and commenters. Dedupe across posts
(one person can engage with many posts — they are ONE lead). Remove anyone in
suppression or already contacted. Output a clean list of net-new engagers.

## Steps

### 1. Load today's posts
```python
import json, pathlib, datetime
today    = datetime.date.today().isoformat()
posts    = json.loads(pathlib.Path(f"state/posts_{today}.json").read_text())
post_urls = [p["postUrl"] for p in posts if p.get("postUrl")]
print(f"Loaded {len(post_urls)} post URLs.")
```

### 2. Scrape engagers via Apify
```python
from scripts.apify import get_post_engagers
raw_engagers = get_post_engagers(post_urls)
print(f"Raw engager records: {len(raw_engagers)}")
```

Each record should contain at minimum: `profileUrl`, `firstName`, `lastName`, `headline`.

### 3. Dedupe by profile URL (one person across many posts)
```python
seen = {}
for eng in raw_engagers:
    url = eng.get("profileUrl", "").strip().rstrip("/")
    if not url:
        continue
    if url not in seen:
        seen[url] = eng
        seen[url]["engaged_posts"] = []
    seen[url]["engaged_posts"].append(eng.get("postUrl", ""))

engagers = list(seen.values())
print(f"Unique engagers after dedupe: {len(engagers)}")
```

### 4. Suppress known contacts
```python
from scripts.state import is_suppressed, is_contacted

net_new = [
    e for e in engagers
    if not is_suppressed(e["profileUrl"]) and not is_contacted(e["profileUrl"])
]
print(f"Net-new after suppression: {len(net_new)}")
```

### 5. Remove the influencers themselves
```python
influencers = json.loads(pathlib.Path("config/influencers.json").read_text())
inf_urls    = {inf["linkedin_url"].strip().rstrip("/") for inf in influencers}

net_new = [e for e in net_new if e["profileUrl"].strip().rstrip("/") not in inf_urls]
print(f"After removing influencers: {len(net_new)}")
```

### 6. Attach post context for personalization
For each engager, store which influencer and post they came from (use the first post
if they engaged with multiple — prefer one with the highest engagement count).

```python
post_map = {p["postUrl"]: p for p in posts}
for eng in net_new:
    source_post = post_map.get(eng["engaged_posts"][0], {})
    eng["source_influencer"] = source_post.get("influencer_name", "")
    eng["source_post_url"]   = eng["engaged_posts"][0]
    eng["source_post_text"]  = source_post.get("text", "")[:300]
```

### 7. Save output
```python
out_path = pathlib.Path(f"state/engagers_{today}.json")
out_path.write_text(json.dumps(net_new, indent=2))
print(f"Saved {len(net_new)} net-new engagers to {out_path}.")
```

## Expected engager object fields
- `profileUrl` — canonical LinkedIn profile URL (primary key throughout the pipeline)
- `firstName`, `lastName`
- `headline` — current title as displayed on LinkedIn
- `engaged_posts` — list of post URLs they engaged with
- `source_influencer` — name of the influencer whose post surfaced them
- `source_post_url` — URL of the specific post (for personalization)
- `source_post_text` — first 300 chars of that post

## Notes
- If engager scraping fails for a post (private post, actor error), log the post URL and
  skip — do not abort the full run.
- The `profileUrl` deduplication key must be normalized (strip trailing slash, lowercase
  domain) to avoid false duplicates.
