# Decision sprite: brief (Victor, 2026-11-11 — unchanged from the version Muse copied)

## What

A decision sprite is a small, single-purpose website that a coding agent
spins up when it needs a human's judgment before starting work. It runs on
a Fly Sprite (Fly.io's persistent sandbox with its own URL), one sprite per
decision.

The site runs an interview the way an optometrist runs an eye exam:
"Better, 1 or 2?" The agent arrives with a first guess at how the human
would decide, and asks only where that guess is weak. Each short round of
answers sharpens the guess and determines the next round. The site shows
the agent's current understanding of how the human decides, so the human
corrects the picture itself, not only the individual questions.

The interview is one straight line of rounds with no branching paths. It
has no fixed length and no completion score: it ends when the human says
they are satisfied. The human never has to leave the site to tell the
agent that answers are waiting; answering is enough to move things forward.

What the interview produces is a decision model: a description of what
this person values and how they trade things off, specific enough that the
agent can settle later questions the interview never covered.

## Why

- **Agents face many small choices mid-implementation.** Stopping to ask
  each one interrupts the human; guessing silently produces work the human
  rejects.
- **A list of answers runs out.** It covers only the questions someone
  thought to ask up front. A model of how the person decides extends to
  the ones nobody anticipated.
- **A fixed questionnaire wastes attention.** It asks what the agent could
  have predicted and misses what it could not. Asking only at the edge of
  the agent's uncertainty spends the human's time where it changes the
  outcome.
- **Only the human knows when they have been understood.** That is why the
  stopping rule is theirs.
- **A chat or terminal prompt is a poor medium for this.** A web page can
  show the evolving model beside the questions.

## First use

The first decision sprite decides the design of the decision sprite
template itself: I answer its questions until we agree on how every later
one should work.

## Interview-screen design prompt (Impeccable, Victor 2026-11-11)

```
/impeccable design the interview screen for a decision sprite, a
single-purpose site where a coding agent learns how one person makes
decisions before it starts work. It runs like an eye exam: "Better, 1 or
2?" Each round is a few short choices, and each answer brings the agent's
picture of how I decide into sharper focus. That picture is the eye chart:
always on screen, blurry where the agent is still guessing, crisp where it
is sure, visibly sharper after every round. Progress is clarity, never
completion: there is no fixed number of rounds, so no progress bar, no
percent, no "step 3 of 10". Rounds count up, and earlier rounds stay
visible as the lenses already tried. Every round ends with the same two
choices: keep going, or I can see clearly now. Stopping produces the
prescription: the finished decision model, stated plainly enough to hand
to someone else. Audience is one person, a founder or engineer pulled out
of other work, often on a phone, giving this a few minutes at a time. The
feel is an exam room: quiet, precise, unhurried, one thing in front of you
at a time. Take the metaphor from the exam's rhythm and optics (focus,
blur, paired lenses, the chart), not from costume: no eyeballs, no
glasses clip art, no medical branding. Not a chatbot, not a survey, not a
dashboard.
```

Design consequences Muse is carrying into the v2 template:
- The decision model is rendered as the eye chart: always visible beside/above the questions; each posture line's sharpness reflects Muse's scored confidence (blurred where unconfirmed, crisp where confirmed by hits).
- No progress bar, percent, or step counts anywhere. Rounds count up (Round 1, 2, 3…); earlier rounds remain visible as the lenses already tried.
- Every round ends with exactly two choices: "Keep going" and "I can see clearly now." Stopping emits the prescription — the decision model as plain, handoff-able text.
- Exam-room feel (quiet, precise, unhurried, one thing at a time), phone-first; metaphor from rhythm and optics only — no eyeballs, glasses clip art, or medical branding. Not a chatbot, not a survey, not a dashboard.
