---
name: design-sprites
description: Run a decision interview as a small website on a Fly Sprite when a coding agent needs a human's judgment before starting work. The agent maps the decision space, predicts the human's answers, asks only the frontier round by round, and keeps a living decision model on the page — rendered as an eye chart that comes into focus — until the human says "I can see clearly now" and receives the prescription: a decision model specific enough to govern implementation decisions the interview never covered. Use when a design or implementation choice has load-bearing ambiguity, the human's time is scarce and fragmented, or a chat back-and-forth would lose the evolving picture. The interview is event-driven: the sprite notifies the agent on submit; the agent never polls. Ships with the full Elixir + Phoenix + Ash template app.
---

# Design Sprites

A design sprite is a small, single-purpose website that a coding agent spins up when it needs a human's judgment before starting work. It runs on a Fly Sprite (Fly.io's persistent sandbox with its own URL) — one sprite per decision. `brief.md` in this skill is the founding brief; read it first.

The site runs the interview the way an optometrist runs an eye exam: "Better, 1 or 2?" The agent arrives with a first guess at how the human decides, asks only where that guess is weak, and each short round of answers sharpens the guess and determines the next round. The human corrects the picture itself — the agent's current decision model, always on the page — not only the individual questions. The interview ends when the human says they are satisfied, and what it produces is a **decision model**: what this person values and how they trade things off, specific enough that the agent can settle later questions the interview never covered.

## When to use one

- The work ahead contains decisions only the human can make, and guessing silently would produce work they reject.
- The human's attention comes in minutes, often on a phone, between other work. A page that holds state beats a chat thread they must scroll and re-explain.
- The decision will keep generating follow-on questions during implementation. A list of answers runs out; a model of how the person decides extends to questions nobody anticipated.

Do not use one for mechanical work (typo fixes, obvious renames, a bug the human already diagnosed), or when the facts are discoverable by reading — finding facts is the agent's job; choosing between them is the human's.

## The interview process

The method is the ask-clarifying-questions interview, moved onto a page:

1. **Map the decision space.** Before the first question, privately enumerate the decisions the task involves and the plausible answers to each. Treat them as independent axes unless one answer removes another axis. Order axes by how much settling each one shrinks the remaining space. **Predict an answer for every axis and note your confidence.** Axes you can already predict with high confidence are not questions; they are the first entries in the decision model. The map itself stays private — never present it or narrate the ordering.
2. **Anchor.** The sprite's design page restates, in one sentence, what you understand the human wants, so they have a cheap redirect point.
3. **Ask the frontier.** Each round asks every unsettled axis whose prerequisites are settled, highest partition power first. Batch independent questions; sequence dependent ones. Do not pad a round with questions you can already predict.
4. **Show the prediction with every question.** Every question carries a visible `My prediction:` line. The predicted answer is always the **first option**, untagged. When your recommendation differs from your prediction, append `(Recommended)` to the recommended option. Position carries the prediction; the tag carries a divergent recommendation.
5. **Update the model after every round.** Score the predictions. A hit confirms the axis and everything it correlates with; a miss tells you where the model is wrong — find the axis the miss generalizes to. Infer tradeoff posture (simplicity vs flexibility, speed vs ceremony, build vs buy…) from concrete answers; never ask explicit tradeoff questions. An unanswered or skipped question proceeds on the prediction, recorded as an assumption — neither a hit nor a miss, and its axis stays unconfirmed.
6. **Stop at clarity.** The stop rule is ~95%: recent predictions on load-bearing questions all hit (including at least one on the axis of the last miss), unasked axes are equally predictable, and a plausible next question would not change the implementation. On the sprite, stopping is the human's button, not the agent's judgment call (see below).
7. **The prescription.** When the interview ends, state the model plainly enough to hand to someone else:
   - **Decisions** — the load-bearing answers, in 1–3 sentences.
   - **How you decide** — bullets naming each tradeoff axis, the side taken, and the reason inferred from the answers, including every prediction/recommendation divergence and every boundary the human reserved for themselves.
   - **Goal** — one line: the outcome and the proof it happened, ending with an autonomy clause.
8. **Govern implementation with the model.** When implementation uncovers a question the interview never reached: if the model predicts the answer at stop-rule confidence, decide silently and log it in the final summary with the model bullet it followed; if not, or the decision sits inside a reserved boundary, re-enter the interview with a new round. When a "how you decide" bullet recurs across interviews, propose it as a durable rule in the summary — never write it into the user's standing instructions unilaterally.

## Event-driven, never polling

The human never leaves the site to announce that answers are waiting, and the agent never polls for them.

- The human edits answers (autosaved continuously) and ends the round with one of two choices: **Keep going** or **I can see clearly now**. Both are submits.
- On submit, the sprite records the submission and **notifies the agent** (the template's notifier sends a mail through the Sprites gateway's Resend connection; the message carries ids and timestamps only, never answer content).
- The notification starts the agent's turn. The agent reads the answers via `GET /admin/answers` (Bearer admin token), then acks with `POST /admin/ack {"round": N}` — only after the ack may the page tell the human the agent picked the submission up. An un-acked submission reads as undelivered on the page; that honesty is deliberate.
- The agent then does its process step: score predictions, update the decision model on the design page (`POST /api/design`), and — unless the human said "I can see clearly now" — post the next frontier round (`POST /api/rounds`). If the human stopped, the agent writes the prescription onto the design page and proceeds to the work.
- If no notifier is configured, the sprite still records submissions and reports them UNDELIVERED. Never substitute a polling loop for the missing notifier.

## Design language: the eye exam

Take the metaphor from the exam's rhythm and optics — focus, blur, paired lenses, the chart — not from costume.

- **The model is the eye chart.** It is always on screen beside the questions. Each line of the model renders blurry where the agent is still guessing and crisp where scored answers have confirmed it; it visibly sharpens after every round.
- **Progress is clarity, never completion.** There is no fixed number of rounds, so: no progress bar, no percent, no "step 3 of 10". Rounds count up (Round 1, 2, 3…), and earlier rounds stay visible as the lenses already tried.
- **Every round ends with the same two choices:** Keep going, or I can see clearly now. Stopping produces the prescription.
- **Feel:** an exam room — quiet, precise, unhurried, one thing in front of you at a time. Phone-first; the audience is one founder or engineer pulled out of other work for a few minutes.
- **Never:** eyeballs, glasses clip art, medical branding. Not a chatbot, not a survey, not a dashboard.

## Stack

**Elixir + Phoenix LiveView + Ash, with SQLite on the sprite's own persistent disk. This is the strong default** — the template in `template/` is exactly this, and new decision sprites are created from it, not rewritten. Per-sprite state lives in `<app dir>/data/` (SQLite `app.db`, `seed.json`, `.admin_token`, `.secret_key_base`). Reach for something heavier (Postgres, a separate host) only when shared access or real concurrency outgrows the sprite's disk.

## Creating a sprite from `template/`

Full runbook: `template/DEPLOY.md`. The shape:

1. **Build the release once** from `template/`: `MIX_ENV=prod mix release` (ERTS bundled), packaged with `scripts/run.sh` at the root. The same artifact deploys to every sprite, unchanged.
2. **Create the sprite** and extract the artifact as the app dir, e.g. `/home/sprite/app`.
3. **Seed it** — the only per-sprite content input. Place a state document at `/home/sprite/app/data/seed.json`; on first boot (empty DB) the app loads it through `DecisionSprite.SeedLoader`, the same loader behind `POST /api/reset`. The document:
   ```json
   {
     "design": {
       "version": 1,
       "title": "Optional display title",
       "sections": [{"heading": "What this is", "status": "decided", "body": "Markdown…"}]
     },
     "rounds": [
       {"n": 1, "status": "open", "submitted_at": null, "anything_else": null,
        "questions": [{"id": "domain_rule", "prompt": "…", "context": "…",
                       "options": [{"value": "split_review_ops", "label": "…", "detail": "…"}],
                       "answer": null}]}
     ]
   }
   ```
   The design sections carry the anchor, the living decision model, and the map's un-asked predictions (correctable in any question's comment — treat a correction as an answer). Round 1 holds the first frontier batch, each question with its `My prediction:` line in the context and the predicted option first.
4. **Admin token:** to pin it, pre-place `data/.admin_token` (mode 0600) before first boot; otherwise the app generates one — read it back from that file and store it safely.
5. **Configure** `data/.env` (0600):
   ```
   PHX_HOST=<sprite>-<suffix>.sprites.app
   SPRITE_NAME=<sprite>
   SUBMIT_NOTIFIER=mail_gateway
   ```
   and label the sprite for the Resend gateway connection so submit notifications can send (labels are replaced wholesale by `sprite config update` — pass the sprite's complete label set in one call).
6. **Register the service:** `sprite-env services create app --cmd /home/sprite/app/run.sh --dir /home/sprite/app --http-port 8080`. `run.sh` generates `data/.secret_key_base` once, migrates, and starts the release.
7. **Make the URL public** (url-auth: public) — the page is the human's front door, no login; the admin/API routes stay behind the bearer token.
8. **Verify:** `GET /health` returns ok with the design version; `GET /admin/answers` with the bearer token returns the seeded rounds verbatim; `GET /questions` shows the open round with its submit button.

### Runtime API (Bearer admin token unless noted)

- `GET /health` — no auth; performs a real DB write+read probe.
- `GET /admin/answers` — the verbatim answers view: rounds, statuses, `submitted_at`, every answer field.
- `GET /api/state` — the full state document.
- `POST /api/rounds` — post the next round. 409 while a round is open unless `replace_open: true`; a snapshotted round is never destroyed.
- `POST /api/design` — replace the design document (bumps the design version); this is how the model on the page gets sharper.
- `POST /admin/ack` — body `{"round": N}`; the agent's explicit "I read it" signal.
- `POST /api/reset`, `POST /api/seed` — replace all content with a state document. Refused with 409 `would_drop_snapshot` if the document would drop a submitted round's snapshot, unless `"force": true`.
- `POST /api/draft` — the page's own autosave flush (session + CSRF); not an agent route.

## Ops routes

- **Sprites CLI** (`sprite`, run from a host with Sprites access): create/destroy sprites, `sprite exec -s <name>` to run commands inside, `sprite config update` for gateway labels, `sprite-env services` inside the sprite for the app service. This is the primary route — script deploys and repairs through it.
- **Fly's remote MCP server** at `https://fly.io/mcp` (OAuth) covers Sprites and Machines as an alternative ops surface — useful for inspecting apps, machines, and sprite state from an MCP client. Note: reading a sprite's runtime state through it may wake a sleeping sprite.

## Hard rules

- **Autosave includes clears.** Every tap and keystroke saves as a draft — and clearing a field is a save: a cleared comment or "Other" text must persist as cleared. (The template carries regression tests for exactly this; a save path that treats an empty value as "no change" silently resurrects deleted text.)
- **Submitted rounds are frozen verbatim.** A submitted round's snapshot never changes and is never overwritten by a later round. Any edit to a submitted round's answers withdraws the submission — the round reopens as a draft and must be re-submitted. Content replacement that would drop a snapshot is refused unless forced.
- **Every question carries an escape hatch:** an **"Other (specify)" radio inside the question's option group** (never a detached box beside a preselected choice) **plus a free-text comment field**. A named choice + comment means the comment qualifies the choice; Other selected means the typed text *is* the answer. Named options are capped at 9 so Other always fits as the 10th.
- **One canonical template.** Per-sprite differences are seed + secrets only — never fork the app for one sprite. Template changes land in the template, then redeploy.
- **Edit sprites in place by default.** Redeploy the release over the existing app dir, preserving `data/`, and verify answers are byte-identical before and after. Destroy-and-recreate is only the fallback for a sprite wedged beyond repair.
- **The model is the deliverable.** Answers without the updated model on the page is a half-finished round; the prescription, not the last answer set, is what the human walks away with.
