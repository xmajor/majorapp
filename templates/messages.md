# Message Templates — SalesKick Outbound

All templates use `{{PLACEHOLDER}}` syntax. Fill before sending.
Never send a message with unfilled placeholders.

---

## Outbound DMs — Initial Contact

### Tier A — angle: pain_ramp_time
> Triggered by: hiring signal OR ramp-time post engagement

---
Hey {{FIRST_NAME}} — saw you engaging with {{INFLUENCER_NAME}}'s post on {{INFLUENCER_NICHE}}.

{{HOOK}}

We're putting together a small live training session with a top B2B sales trainer on exactly this — ramp frameworks, onboarding playbooks, the works. Free, 30 minutes, zero pitch.

Thought you'd find it useful given what you're building at {{COMPANY}}.

Worth 30 mins? {{BOOKING_LINK}}

---

### Tier A — angle: pain_quota
> Triggered by: quota/attainment post engagement

---
Hey {{FIRST_NAME}} — came across your engagement on {{INFLUENCER_NAME}}'s content and it resonated.

{{HOOK}}

We're running a free 30-min working session with one of the top B2B sales trainers in the space — focused entirely on quota attainment levers. No pitch, just actionable frameworks.

Given your role at {{COMPANY}}, thought it might be worth 30 minutes.

Grab a spot here: {{BOOKING_LINK}}

---

### Tier A — angle: trigger_funded
> Triggered by: recent funding announcement

---
Hey {{FIRST_NAME}} — congrats on the raise!

{{HOOK}}

We're running a free 30-min session with a senior B2B sales trainer specifically on this — building the onboarding process before the new hires show up. No pitch, just a working session.

Would it be useful to you and the team at {{COMPANY}}?

{{BOOKING_LINK}}

---

### Tier A — angle: trigger_new_leader
> Triggered by: recent leadership change (< 6 months in role)

---
Hey {{FIRST_NAME}} — noticed you're relatively new to the {{COMPANY}} role. The first 90 days set the trajectory.

{{HOOK}}

We're running a free 30-min live session with a sales trainer who's helped dozens of new sales leaders stand up a repeatable process in their first quarter. Zero pitch — just the playbook.

Worth 30 mins? {{BOOKING_LINK}}

---

### Tier A — angle: trigger_hiring
> Triggered by: open AE/SDR job postings

---
Hey {{FIRST_NAME}} — saw {{COMPANY}} is building out the sales team (nice to see the growth).

{{HOOK}}

Running a free 30-min training session on exactly this — cutting new rep ramp time. Most teams we work with see a material difference in time-to-first-deal after implementing the framework. No pitch.

Worth a look? {{BOOKING_LINK}}

---

### Tier B — angle: generic_credibility
> Used when no strong trigger signal fires

---
Hey {{FIRST_NAME}} — saw you engaging with {{INFLUENCER_NAME}}'s content.

{{HOOK}}

We put on a free 30-min live training session with a top sales trainer — focused on practical quota attainment tactics your team can use right away. No product pitch, just value.

Would it be relevant for {{COMPANY}}?

{{BOOKING_LINK}}

---

## Follow-Up Templates (HeyReach sequence steps)

### Follow-up 1 (Day 3)
---
Following up on this, {{FIRST_NAME}} — wanted to make sure it didn't get buried.

The session is free and 30 minutes. We're keeping it to a small group so the trainer can go deep on your specific situation.

Still worth a look: {{BOOKING_LINK}}

---

### Follow-up 2 (Day 7)
---
Last one from me, {{FIRST_NAME}} — if the timing isn't right, totally understand.

If quota attainment or ramp time becomes a priority at {{COMPANY}}, the offer stands.

You can grab a spot anytime: {{BOOKING_LINK}}

---

---

## Inbox Reply Playbook

### book_meeting — they said yes / want to book

---
Great, {{FIRST_NAME}}! Here's the link to grab a time: {{BOOKING_LINK}}

Pick whatever works best — looking forward to it.

---

### question_product — asking what we do / what SalesKick is

---
Sure! SalesKick is a sales-ops platform that helps B2B sales leaders improve quota attainment and cut new rep ramp time. We do it through structured coaching frameworks, not just theory.

The free session is a live working call with one of our trainers — it's genuinely just a session, not a sales call. You'll walk away with something usable.

Easiest way to see if it's relevant: {{BOOKING_LINK}} — 30 minutes, cancel anytime.

---

### objection_time — too busy right now / bad timing

---
Totally get it, {{FIRST_NAME}} — timing is everything.

When would be a better time to circle back? Happy to reach out in a few weeks or next quarter, whichever works better.

No pressure either way.

---

### objection_not_relevant — not a fit / no sales team

---
Appreciated the honest reply, {{FIRST_NAME}} — makes sense if it's not the right fit right now.

Best of luck with the team at {{COMPANY}}.

---

### referral — they pointed you to someone else

---
Thanks {{FIRST_NAME}} — really appreciate the intro. I'll reach out to {{REFERRAL_NAME}} directly.

And if the timing ever shifts for you, feel free to grab a session too: {{BOOKING_LINK}}

---

### escalate — pricing / legal / contract / complaint
**Do not reply.** Log to `state/escalations.jsonl` with full message text and flag for human.
Never discuss pricing, contracts, legal terms, or complaints in automated replies.

---

## Personalization rules
1. Always use first name only (never "Hi [Full Name]").
2. Reference the specific influencer by name, not "someone you follow".
3. Keep messages under 120 words. Long messages get ignored.
4. No emoji unless the lead used them first.
5. No exclamation points except after "Great" in booking confirmation.
6. Do not use "I wanted to reach out" or "I hope this finds you well".
7. One call to action per message. Always the booking link.
