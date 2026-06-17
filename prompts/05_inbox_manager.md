# Stage 5 — Inbox Management

Run every 1–2 hours. This stage handles all replies to your HeyReach sequences.

## Goal
Read new inbox messages, classify intent, respond according to the playbook in
`templates/messages.md`, book meetings, suppress opt-outs, and escalate anything
outside the playbook.

## Steps

### 1. Fetch new inbox messages
```python
import json, pathlib, datetime
from scripts.heyreach import get_inbox_messages

cfg      = json.loads(pathlib.Path("config/pipeline.json").read_text())
messages = get_inbox_messages(since_hours=cfg["inbox"]["poll_interval_hours"])
print(f"New messages: {len(messages)}")
```

### 2. Classify each message

For each message, determine intent from the reply text:

| Class | Triggers | Action |
|-------|----------|--------|
| `opt_out` | "stop", "unsubscribe", "remove me", "not interested", "leave me alone" | Suppress + stop HeyReach sequence |
| `book_meeting` | "yes", "interested", "let's talk", "book", "calendar", "when works", "sounds good" | Send booking link reply |
| `question_product` | "what is", "how does", "tell me more", "what do you do" | Send product-context reply + booking link |
| `objection_time` | "busy", "not now", "bad timing", "reach out later", "next quarter" | Send future-ping reply, pause sequence |
| `objection_not_relevant` | "not our use case", "we don't have reps", "not a fit" | Acknowledge, suppress |
| `referral` | "talk to [name]", "contact [name]", "reach out to our [title]" | Extract referral, add to engagers for next run |
| `meeting_booked` | Calendly confirmation / "just booked" | Log to meetings.jsonl, stop sequence |
| `escalate` | Pricing, legal, complaint, contract terms | Flag for human |
| `other` | Anything else | Hold, flag for human review |

### 3. Handle each class

#### opt_out
```python
from scripts.state import suppress, append_audit
from scripts.heyreach import stop_sequence

suppress(msg["profileUrl"])
stop_sequence(msg["profileUrl"])
append_audit({"event": "opt_out", "profile_url": msg["profileUrl"], "date": today})
```

#### book_meeting
```python
from scripts.heyreach import reply_to_message

booking_link = cfg["booking"]["link"]
body = (
    f"Great, {msg['firstName']}! Here's the link to grab time: {booking_link}\n\n"
    "Pick whatever works best for you — looking forward to it."
)
reply_to_message(msg["conversationId"], body)
```

#### question_product
Load the "product context" template from `templates/messages.md > inbox > product_context`
and reply with a 2–3 sentence description + booking link. Keep it conversational.

#### objection_time
Load `templates/messages.md > inbox > future_ping`. Acknowledge timing, offer to reach
back in 4–6 weeks, ask for the best time to reconnect.
Update lead's `follow_up_date` in `state/contacted.json`.

#### objection_not_relevant
Acknowledge gracefully. Do not argue. Suppress.

#### referral
Extract the referred name/title from the message text. Add a new lead record to
`state/referrals.jsonl` for manual review and next-run injection.

#### meeting_booked
```python
from scripts.state import append_meeting

append_meeting({
    "profile_url":  msg["profileUrl"],
    "name":         f"{msg['firstName']} {msg['lastName']}",
    "company":      msg.get("company", ""),
    "booked_at":    datetime.datetime.utcnow().isoformat(),
    "booking_link": cfg["booking"]["link"],
})
```

#### escalate / other
```python
from scripts.state import append_escalation

append_escalation({
    "reason":      "inbox_escalation",
    "class":       intent_class,
    "profile_url": msg["profileUrl"],
    "message":     msg["text"][:500],
    "date":        today,
})
```

### 4. Print inbox summary
```
=== Inbox Run — {datetime} ===
New messages:      {n}
Opt-outs:          {n}  → suppressed
Booking requests:  {n}  → booking link sent
Questions:         {n}  → product reply sent
Objections:        {n}  → future-ping / suppressed
Referrals:         {n}  → queued for next run
Meetings booked:   {n}
Escalated:         {n}  → state/escalations.jsonl
Other (held):      {n}
================================
```

## Response tone guidelines
- Friendly, direct, brief (3–5 sentences max).
- Never pushy or high-pressure.
- Always give them an out (they can ignore the booking link).
- Match the conversational register of their reply.
- Do not mention "SalesKick" in the first follow-up reply — keep the training/workshop
  frame until they ask for company details.
- Escalate immediately on any legal, compliance, or pricing inquiry.
