# Stage 1 — Monitor Influencers

## Goal
Fetch all posts published by the 20 ICP influencers in the last N days and save them
so stage 2 can extract engagers.

## Steps

### 1. Load influencer list
```python
import json, pathlib
influencers = json.loads(pathlib.Path("config/influencers.json").read_text())
profile_urls = [inf["linkedin_url"] for inf in influencers]
print(f"Loaded {len(profile_urls)} influencer profiles.")
```

### 2. Load pipeline config
```python
cfg      = json.loads(pathlib.Path("config/pipeline.json").read_text())
days_back = cfg["apify"]["days_back"]
```

### 3. Scrape posts via Apify
```python
from scripts.apify import get_linkedin_posts
posts = get_linkedin_posts(profile_urls, days_back=days_back)
print(f"Fetched {len(posts)} posts.")
```

If the Apify MCP is connected, prefer calling it directly with the same inputs from
`config/pipeline.json > apify.actors.post_scraper`.

### 4. Tag each post with influencer metadata
For each post, merge in the matching influencer record (name, niche, why_icp) so
downstream stages have context for personalization.

```python
url_to_inf = {inf["linkedin_url"]: inf for inf in influencers}
for post in posts:
    profile_url = post.get("authorProfileUrl", "")
    inf_data    = url_to_inf.get(profile_url, {})
    post["influencer_name"]  = inf_data.get("name", "")
    post["influencer_niche"] = inf_data.get("niche", "")
```

### 5. Save output
```python
import datetime
today = datetime.date.today().isoformat()
out_path = pathlib.Path(f"state/posts_{today}.json")
out_path.write_text(json.dumps(posts, indent=2))
print(f"Saved {len(posts)} posts to {out_path}.")
```

## Expected post object fields
Key fields returned by the Apify actor (confirm against actual actor output):
- `postUrl` — canonical LinkedIn post URL (used as key in stage 2)
- `authorProfileUrl` — profile URL of the author
- `authorName` — display name
- `text` — post body (used for signal detection in stage 3)
- `publishedAt` — ISO timestamp
- `likeCount`, `commentCount`, `repostCount`
- `influencer_name`, `influencer_niche` — added by step 4 above

## Notes
- If an influencer's profile returns no posts (private, throttled), log a warning but
  do not abort the run.
- Posts with `likeCount + commentCount < 10` are low-signal; you may skip them to
  reduce Apify cost, but keep the threshold configurable in `pipeline.json`.
