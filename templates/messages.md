# Message Templates — SalesKick Outbound (Show-Rate Course)

All templates use `{{PLACEHOLDER}}` syntax. Fill before sending. Never send a
message with unfilled placeholders.

Placeholders (filled in stage 4, `prompts/04_push_to_heyreach.md`):
- `{{FIRST_NAME}}` — lead first name
- `{{COMPANY}}` — lead company / brand
- `{{INFLUENCER_NAME}}` — the influencer whose post they engaged with
- `{{HOOK}}` — angle hook line from `config/lead_scoring.json > angles`
- `{{OFFER}}` — angle offer line (already contains the show-rate course link)
- `{{BOOKING_LINK}}` — https://www.saleskick.com/show-rate-course

The offer is the **free show-rate course**, not a call. Keep it value-first; the
course IS the call-to-action.

---

## Outbound DMs — Initial Contact

### Tier A — angle: show_rate_fix
> Triggered by: show-rate / no-show post engagement or complaint

---
Hey {{FIRST_NAME}} — saw you in the comments on {{INFLUENCER_NAME}}'s post.

{{HOOK}}

{{OFFER}}

Figured it might be relevant to what you're running at {{COMPANY}}.

---

### Tier A — angle: speed_to_lead
> Triggered by: running paid traffic to a booking calendar

---
Hey {{FIRST_NAME}} — noticed your engagement on {{INFLUENCER_NAME}}'s content.

{{HOOK}}

{{OFFER}}

No pitch — just the framework you can hand to your setters today.

---

### Tier A — angle: setter_closer_handoff
> Triggered by: closer/setter post + a high-ticket offer

---
Hey {{FIRST_NAME}} — caught your comment on {{INFLUENCER_NAME}}'s post.

{{HOOK}}

{{OFFER}}

Thought it'd be useful given the team you're running at {{COMPANY}}.

---

### Tier A — angle: scaling_sales_team
> Triggered by: hiring closers/setters or scaling the team

---
Hey {{FIRST_NAME}} — saw {{COMPANY}} is building out the sales team.

{{HOOK}}

{{OFFER}}

Worth a look before the next closer/setter starts.

---

### Tier A — angle: high_ticket_credibility
> Triggered by: high-ticket offer + large audience, no sharper signal

---
Hey {{FIRST_NAME}} — saw you engaging with {{INFLUENCER_NAME}}'s content.

{{HOOK}}

{{OFFER}}

---

### Tier B — angle: generic_credibility
> Used when no strong trigger fired

---
Hey {{FIRST_NAME}} — saw you following {{INFLUENCER_NAME}}'s stuff.

{{HOOK}}

{{OFFER}}

Would it be relevant for {{COMPANY}}?

---

## Follow-Up Templates (HeyReach sequence steps)

### Follow-up 1 (Day 3)
---
Following up, {{FIRST_NAME}} — wanted to make sure this didn't get buried.

The show-rate course is free and self-paced. Most teams find the no-show recovery
sequence alone moves the number within a couple weeks.

{{BOOKING_LINK}}

---

### Follow-up 2 (Day 7)
---
Last one from me, {{FIRST_NAME}} — if show rate isn't a priority right now, no worries.

If it becomes one at {{COMPANY}}, the course is here anytime: {{BOOKING_LINK}}

---

---

## Inbox Reply Playbook

### book_meeting — they're interested / want the course / want to talk

---
Awesome, {{FIRST_NAME}}! Here's the free show-rate course: {{BOOKING_LINK}}

Start with the no-show recovery module — that's the fastest win. If you want to
talk through applying it to {{COMPANY}}, just say the word and I'll set it up.

---

### question_product — what is this / what's SalesKick / how does it work

---
Sure! SalesKick is a sales-ops platform for high-ticket coaching and agency teams —
we help you get more of your booked calls to actually show up and close.

The show-rate course is genuinely free and not a sales call: it's the exact
confirmation, reminder, and no-show recovery system our clients use. You can go
through it at your own pace here: {{BOOKING_LINK}}

---

### objection_time — too busy / bad timing

---
Totally get it, {{FIRST_NAME}}. The course is self-paced, so it'll keep — bookmark
it for when show rate moves up the list: {{BOOKING_LINK}}

Want me to check back in a few weeks?

---

### objection_not_relevant — not a fit / no sales calls / no team

---
Appreciate the honest reply, {{FIRST_NAME}} — makes sense if booked calls aren't part
of how {{COMPANY}} sells right now. Best of luck with it.

---

### referral — they point you to someone else (e.g. their sales lead)

---
Thanks {{FIRST_NAME}} — appreciate it. I'll send {{REFERRAL_NAME}} the show-rate course
directly. And it's here for you too anytime: {{BOOKING_LINK}}

---

### escalate — pricing / contract / legal / complaint
**Do not reply.** Log to `state/escalations.jsonl` with the full message and flag for
a human. Never discuss pricing, contracts, or legal terms in an automated reply.

---

## Personalization rules
1. First name only (never "Hi [Full Name]").
2. Reference the specific influencer by name, not "someone you follow".
3. Under 120 words. Long DMs get ignored.
4. No emoji unless the lead used them first.
5. One call to action per message — always the show-rate course link.
6. Don't open with "I wanted to reach out" or "I hope this finds you well".
7. Lead with their pain (show rate / no-shows), not with SalesKick.
