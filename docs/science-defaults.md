# Bergmönch defaults and the evidence behind them

Every feature follows these defaults. Tags: [F] read in a fetched source, [S] search snippet only, [M] recalled; check [S]/[M] before quoting numbers.

| Setting | Default | Why |
|---|---|---|
| Scheduler | FSRS on, parameters fitted when enough reviews | FSRS-6 beats SM-2 for 99.6% of users in the open benchmark [F] |
| Desired retention | 90%, slider 70–97%, warning above 95% | Anki default; workload rises steeply above 90% [F]; no % is "optimal" (85% rule is from ML classifiers) [S] |
| New cards a day | 10, shown with its steady-state workload (≈10 reviews per new card a day) | New cards drive backlog; workload, not a magic number, is the honest guide |
| Grading | Simple (Forgot / Got it) for new users, Full (4 buttons) optional | 2 vs 4 buttons equally accurate for FSRS [S]; removes Hard misuse |
| Answer | Full answer always shown before grading | Self-grading overrated 55% without reference vs 25% with it [S] |
| Typed answers | Only where the deck's template asks; diff shown, learner still grades | Overt vs covert retrieval g=0.17 [S]; never auto-grade |
| Learning steps | 1 m, 10 m; relearning 10 m | Anki defaults; one short same-day repeat then next day [F] |
| Relearning goal | One correct recall per day | 3 spaced sessions 68% vs 26% for 3 recalls in one session [S] |
| Exam date | Intervals capped at the Cepeda optimal gap for the days left (≈43% at 7 d, 23% at 35 d, 17% at 70 d, 8% at 350 d), and always before the exam | Cepeda et al. 2008 [F] |
| Audio | Question audio plays on show, answer audio on reveal; replay button | Anki parity |
| Leeches | 8 lapses, then ask to rewrite/split/suspend | Anki default; leeches need rewriting |
| Theme | GEIST dark; Match system, Light, Dark and the Gruvbox look are in Settings | Design choice, not evidence |
| Calendar / reminders | Days studied, no streak; reminder off until chosen, only when cards are due, no guilt wording | Broken streaks reduce engagement [S]; no time-of-day evidence [S] |
| Sync | Self-hosted Anki sync server only; never AnkiWeb | AnkiWeb terms close it to third-party clients |
| Not built on purpose | Leaderboards, XP, multiple choice, "3× correct today", hard time limits | Weak or negative evidence |
