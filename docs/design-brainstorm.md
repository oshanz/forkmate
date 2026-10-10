# Chess on Commanded: Design Brainstorm

Originally written 2026-09-30, trimmed 2026-10-10 to what is still open. The MVP rules engine, the tree-based `Game` aggregate, projections, the LiveView board with branch overview, and play-vs-bot are built; see `CLAUDE.md` for the current architecture.

## Branching model (as built)

A game is a tree of positions in one stream. Rewinding writes nothing; `MakeMove` carries `from_node_id`, and playing from a node that already has a child creates a branch (`BranchCreated` plus `MoveMade`). Only the player whose colour is to move at a node may play or branch from it. A mate, stalemate or draw ends only its own branch; resignation or an agreed draw ends the whole game.

**Open questions**

- How do clocks behave across branches? A clock belongs to one line of play, and restoring each node's clocks on branching is exploitable. Options: untimed or correspondence-style play, or a clock that runs only on the line both players are on.
- Which branch decides the rating?
- Cap branches per game, so the stream and the overview stay manageable?
- Let players hide branches? Events are permanent, so it would be a read-model flag only.

## Not built yet

**Clocks and timeouts** (the biggest risk)

- Aggregates stay deterministic, so time enters as data on the command. The server stamps `MakeMove` with the receive time; `MoveMade` should carry remaining time per side and the move timestamp.
- A process manager starts on `GameStarted`, schedules a timer for the side to move, reschedules on each `MoveMade`, and dispatches `ClaimTimeout`, which the aggregate validates against the stored clock. Commanded has no built-in timer, so use `Process.send_after` in a supervised process or an Oban job.
- Timers vanish on restart: rebuild them from an `active_timers` read model of active games.
- Add an increment or delay if Fischer or Bronstein controls are supported.
- Optional house rule: a disconnect timer that claims a win after N seconds.

**Draw claims.** Fifty-move, repetition and insufficient material currently end the branch automatically. Decide whether to keep that or add a `ClaimDraw` command. Draw offers should expire when the offerer moves.

**Presence.** Show where each player currently is in the branch overview (`Phoenix.Presence` or a shared cursor); today only your own position is shown.

**Event store hygiene**

- Upcasters (`Commanded.Event.Upcaster`) to migrate old payloads at read time.
- A custom serializer with explicit type names, so renaming a module does not break stored events.
- `correlation_id`, `causation_id` and the acting user id as metadata on every command.
- A client-supplied command `uuid`, so a retried `MakeMove` is not applied twice.
- Keep PII out of events, or plan crypto-shredding.

**Testing.** Property tests with StreamData (any legal move sequence never leaves the mover's king in check) and replay of real PGN games asserting the final FEN. Perft tests already exist.

**Replay and export.** Step through any game or share a link to a ply. PGN export, with branches as variations, is a fold over `MoveMade` events.

## Later

- **Accounts and lobby:** `Player` (profile, rating, `player_stats` read model), `Challenge` or `Lobby` process manager that pairs `ChallengeCreated` events and dispatches `StartGame`. Decide whether guests can play. Keep these separate from `Game` so its stream stays small.
- **Tournaments:** a `Tournament` aggregate with a process manager that pairs rounds (Swiss or round robin) from `GameEnded` events.
- **Spectators:** subscribe to the game's PubSub topic; add delayed broadcast, commentary and embeds.
- **Analysis:** an event handler sends finished games to Stockfish and emits `GameAnalysed`; the same data can feed anti-cheat signals (move times and engine agreement) and puzzles from positions where the played move differed sharply from the engine's best.
- **Opening explorer:** project all `MoveMade` events into a move-tree read model with win rates by position.
- **Correspondence chess:** days-per-move clocks fit the same clock model, with timers backed by Oban.
- **Variants:** Chess960 and others change only the rules module and the starting position in `GameStarted`.

## Open questions

- Single node or clustered at launch?
- Accounts mandatory, or guest play?
- Which time controls ship, and how do clocks work across branches?

## Suggested order for what remains

1. Clocks and the timeout process manager.
2. Draw claim and offer-expiry rules.
3. Event metadata, idempotency and upcasters.
4. Replay and PGN export.
5. Accounts, lobby, ratings.
6. Spectators and the later ideas.
