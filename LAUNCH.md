# Launch plan

The whole launch hangs on one sentence: **"monitoring built for your AI to read, not for you."**

That sentence is the entire moat. If it lands, the tool spreads; if it doesn't, the code doesn't matter. So every channel below uses the same core idea, varied for the audience.

---

## Pre-launch checklist (do before you post anywhere)

1. Publish to npm: `npm publish --access public`. Confirm `npx ai-healthcheck@latest help` works from a fresh shell.
2. Create the GitHub repo, push the code, add MIT topic + a real description.
3. Generate the one good screenshot you'll use everywhere:
   - Terminal output (colored), failing checks visible, your stack shown (Next/Supabase/Stripe).
   - Below it: a 5-line snippet of the AI JSON — `instructions_for_ai`, `questions_to_investigate`, one failed check. Crop to ~600px.
4. Record a 30-second screencap (use Quicktime or [tape.gg](https://tape.gg)): `npx init` → `run --ai-json` → drop file into Claude/ChatGPT → answer appears. This is the asset that does 80% of the work on every channel.
5. Pre-write 3 things people will ask in the first hour and stage answers as comments-in-waiting:
   - "How is this different from UptimeRobot?" → "UptimeRobot pings a URL and pages a human. This runs ~10 stack-aware checks and outputs a file your AI can triage in one paste."
   - "Why YAML config, not code?" → "So a non-coder vibe-shipper using Cursor can edit it. Code config would lose the audience."
   - "Where's the hosted version?" → "Coming. The CLI is the wedge — it has to be useful on its own first."

---

## Channel 1: Hacker News (highest leverage, hardest to land)

**Submit Tuesday or Wednesday, 8:30am PT** (after the Asia/EU wave, before the US wakes up — peak rising-to-front-page window).

**Title** (pick the strongest of these — A/B by gut, don't overthink):

- ✅ **Show HN: ai-healthcheck — uptime monitoring designed for your AI to read** ← lead candidate
- Show HN: A CLI that emits monitoring JSON optimized for LLMs to triage
- Show HN: Drop this JSON into Claude and ask "what's broken?"

Why the first one wins: it has *Show HN* (the cheap signal HN trusts), the package name (memorable, googlable), and a 9-word positioning sentence. No emojis, no hype words.

**First comment** (post yourself, within 60 seconds of submission):

> Author here. The thing I kept hitting: I'd ship something on Vercel, paste the error log into Claude, fix it, ship again. Every monitoring tool I tried wanted me to look at a dashboard. I didn't want a dashboard. I wanted a file I could paste into a chat window.
>
> So this is that file. The CLI runs ~10 smoke tests (HTTP, SSL, DB connectivity, env vars, Stripe key shape, npm audit, sitemap, robots) and emits an `.ai.json` that starts with `instructions_for_ai` and `questions_to_investigate`. Drop it into Claude/ChatGPT, ask "what's broken?", get a triaged answer.
>
> Conscious choices:
> - Stripe live API calls are opt-in (`--with-network`). Don't want your secret key hitting the wire on every CI run.
> - YAML config because the audience (indie hackers, Cursor users) isn't going to write JS for this.
> - No hosted version yet. Wedge first, SaaS later if it lands.
>
> Open to "this is dumb because X" — that's the most useful feedback at this stage.

**Engage in the thread for the first 4 hours.** Don't just reply with thanks. Reply with substance. HN rewards authors who debate their critics in good faith.

---

## Channel 2: Indie Hackers

**Format: Post, not Milestone.** IH milestones get ~30 views; well-titled posts get 1000+.

**Title:** *I built an open-source CLI in a weekend because every monitoring tool was designed for the wrong workflow*

**Hook (first paragraph — IH grades this hard):**

> Indie hackers don't read monitoring dashboards. We ship a thing on Vercel, paste the error into Claude, fix it, ship again. So I made a tool that fits that loop: it runs smoke tests on your stack and outputs a JSON file engineered to be dragged into an AI chat. The differentiator isn't the checks — those exist everywhere. It's that the JSON file *starts* with a checklist of questions for the LLM to answer, so the triage takes one paste instead of a back-and-forth.

**Body:**
- 1 paragraph on the problem (audience: us)
- 1 paragraph on what it does (terminal screenshot)
- 1 paragraph on the JSON design (snippet of `instructions_for_ai` + `questions_to_investigate`)
- 1 paragraph on what's NOT in v1 and why (anti-scope = credibility on IH)
- 1 line CTA: try `npx ai-healthcheck run --ai-json`, GitHub link

End with: "what would you want this to check that I'm missing?" — IH loves being asked.

---

## Channel 3: Subreddits

Post on **different days**, NOT the same day. Reddit moderators cross-flag if you blast multiple subs.

| Sub | Day | Angle | Title |
|---|---|---|---|
| **r/SideProject** | Mon | Builder pride | *I built a CLI in a weekend that runs smoke tests on your stack and outputs a JSON file you can paste into ChatGPT to triage what's broken* |
| **r/webdev** | Wed | Technical | *Made an open-source monitoring CLI that emits JSON optimized for LLMs — drop the file into Claude and ask "what's broken?"* |
| **r/nextjs** | Thu | Stack-specific | *Drop-in smoke tests for Next + Supabase + Stripe — outputs JSON you can paste into Claude to triage failures* |
| **r/devops** | Fri | Skeptical-aware | *An experiment: monitoring JSON designed for LLMs to read, not dashboards. Roast it.* |
| **r/programming** | (skip unless huge) | — | Programming gets cranky about Show & Tell posts; skip unless HN front page already validated. |

**Avoid:** r/SaaS (wrong audience — they want hosted things), r/Entrepreneur (won't get it), r/ChatGPT (overrun with prompt-bros).

For every subreddit, **read the sidebar rules** before posting. r/webdev requires Showoff Sat for self-promo; r/devops has a flair requirement. Use the right flair.

---

## Channel 4: Dev newsletters / weekly roundups

Cold email these — short, plain text, no attachments, with the live URL.

1. **Bytes** (bytes.dev — Tyler McGinnis): hits 200k JS devs. They like quirky angles; "monitoring for AI to read" fits.
2. **Node Weekly** (Cooper Press): straightforward; submit via [their form](https://nodeweekly.com/submit).
3. **Console** (console.dev): explicitly indexes "interesting tools for developers." Perfect match. Submit via [their form](https://console.dev/submit/).
4. **TLDR Newsletter** (tldr.tech): low hit rate but if they pick it, it's a flood. Email tldr@tldrnewsletter.com.
5. **Indie Hackers newsletter** (curated from posts): the IH post above is the submission.

Cold-email template (keep it under 80 words):

> Subject: One-paragraph tool for [Newsletter name]
>
> Hi [name],
>
> Shipped a small open-source CLI this weekend: `npx ai-healthcheck`. It runs ~10 smoke tests on a web stack (HTTP, SSL, DB, env vars, Stripe key shape, etc.) and outputs a JSON file engineered to be pasted into Claude/ChatGPT for triage — the file embeds the LLM prompt up front so "what's broken?" works in one paste.
>
> GitHub: [link]. Happy to answer any questions.
>
> Cheers,
> [you]

---

## Channel 5: X / LinkedIn / personal network (use the screencap)

The 30-second screencap is the move. Post it with one line:

> Every uptime monitor is designed for you to read. I built one designed for your AI to read. `npx ai-healthcheck run --ai-json` → drag into Claude → ask "what's broken?" → done. MIT, weekend project.

Pin a reply with the GitHub link (X downranks tweets with outbound links in the body).

---

## Day-of-launch timing (suggested)

| Time (PT) | Action |
|---|---|
| 08:30 | Submit HN |
| 08:35 | Post first author-comment on HN |
| 09:00 | Post on IH |
| 09:30 | Post screencap on X (no link in body, link in first reply) |
| 10:00 | Post on r/SideProject |
| All day | Reply to every comment within 30 min for the first 4 hours |
| Day 3 | If HN traction was real, write a follow-up: "What I learned launching ai-healthcheck on HN" — IH eats that up |

---

## What "success" looks like at each tier

- **Floor (most likely):** 200 GitHub stars, ~500 npm installs in week 1, 5–10 issues, a couple of substantive blog mentions. Validates the positioning; gives you data for a hosted version.
- **Mid:** HN front page top-10, 2k stars, 5k installs, real maintenance load. You now have to decide: pure OSS, or build the SaaS now.
- **Ceiling:** Front-page #1, AI-influencer retweets, picked up by Bytes/Console, 8k+ stars in week one. This is the "drop everything and build the hosted version" outcome.

The positioning is the variable. If "monitoring built for your AI to read" doesn't make people lean forward, no amount of better code or better launch tactics fixes it. So your real job today: A/B-test that sentence on three friends. If two of three don't immediately say "oh, that's clever," rewrite the sentence before you post.

---

## What I'd push back on if I had time to convince you

- **"vibe-coders" is in your audience list.** Don't use that word in the launch copy itself — it dates fast and reads cringe to half the audience. "Indie hackers / Cursor users / people shipping side projects" is the same audience, sounds less like a 2024 meme.
- **Don't show a Claude-specific demo.** Show ChatGPT first. There are ~10x more ChatGPT users than Claude users among indie hackers, and Claude users will figure it out anyway. (Pet preference of the audience, not yours.)
- **Don't list the SaaS roadmap on the README yet.** It pre-poisons the OSS launch — people show up expecting a hook. Keep the "what's coming" section vague.
