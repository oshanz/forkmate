# Chess on Commanded: Design Brainstorm

2026-09-30

## Goals and scope

The aim is an online chess game where every game is an append-only event stream, built on Elixir with Commanded (CQRS/ES framework) and EventStore (Postgres-backed store).

**MVP**

- Two players play a full, rules-correct game (all legal moves, castling, en passant, promotion).
- Game ends by checkmate, stalemate, resignation, agreed draw, threefold repetition, fifty-move rule or timeout.
- Live board for both players; game history and replay; rewind to any earlier position, play a different move to start a branch, and see every branch in one overview.

**Later**

- Matchmaking and lobbies, Elo ratings, tournaments, analysis and engine integration, anti-cheat signals, variants (Chess960, blitz-only pools).

**Constraints to decide early**

- Real-time latency target (a move should reach the opponent in under 200 ms).
- Single node or clustered from day one (Commanded supports distribution via Swarm/Horde-style registries).
- Whether guests can play or accounts are mandatory.

## Branching model

A game is a tree of positions in one stream: rewinding means choosing an earlier node, and playing a different move from it starts a branch.

```
Start ── 1.e4 ── 1...e5 ── 2.Nf3 ── 2...Nc6 ── 3.Bb5     main line
  │        └───── 1...c5 ── 2.Nf3                         branch from 1.e4
  └─ 1.d4 ── 1...d5                                        branch from the start position
```

Each fork is a position that has a second child; the overview draws every path from the start position.

- **Node:** id, parent id, ply, move (SAN), resulting FEN, who moved, remaining clocks, status.
- **Rewind writes nothing.** The client picks an earlier node to view; only playing a move appends an event.
- **`MakeMove` carries `from_node_id`.** If that node has no child yet, the move extends the line. If it already has one, the move creates a branch and the aggregate also emits `BranchCreated`.
- **Who may branch:** only the player whose colour is to move at that node. Nobody can play the opponent's moves, and no consent step is needed to try another idea of your own.
- **Concurrency:** the aggregate handles one command at a time, so both players moving in different branches at once are simply serialised.

| Approach | How it works | Trade-off |
| --- | --- | --- |
| Tree in one stream (recommended) | One `Game` aggregate; each move references its parent node | One consistent history and a simple overview; the stream grows with every branch and results need branch-aware rules |
| Fork into a new game | `BranchGame` copies history up to a ply into a new `Game` stream with `parent_game_id` and `fork_ply` | Each branch is an ordinary game with the simple rules; the overview must join streams and history is duplicated |

**Branch overview**

- Read model `nodes` (game id, node id, parent id, ply, SAN, FEN, mover, status, time). Load a game's tree with one recursive CTE, or fetch the rows and build the tree in memory.
- Draw it as a git-style graph in LiveView SVG: one lane per branch, long single-child runs collapsed, the main line highlighted.
- Mark where each player currently is (Phoenix.Presence or a cursor kept in the LiveView) and the result at each branch tip: mate, stalemate, resigned or still open.
- Clicking a node previews its board; if it is your move there, playing a move creates a branch.

**Open questions**

- Must the opponent accept a rewind, or can each player branch freely on their own turn? The design above assumes free branching.
- Which branch decides the result and the rating? One option: resignation or an agreed draw ends the whole game, while mate or stalemate ends only its branch.
- Do clocks apply? A clock belongs to one line of play. Restoring each node's clocks on branching is exploitable, so consider untimed or correspondence-style play, or a clock that runs only on the line both players are on.
- Should branches per game be capped, so the stream and the overview stay manageable?
- Can players hide branches? Events are permanent, so hiding would be a read-model flag only.

## Domain model

Start with one `Game` aggregate per game; the stream ID is the game ID, and every rule check happens inside it. The game is a tree of positions, not a line (see Branching model).

| Command | Emits | Rejected when |
| --- | --- | --- |
| `StartGame` | `GameStarted` | game already exists |
| `MakeMove` | `MoveMade` (with node id and parent node id), `BranchCreated` when the parent already has a child, plus `CheckDeclared` and/or `GameEnded` | unknown node, not your colour to move at that node, illegal move, node already ended |
| `Resign` | `GameEnded` (resignation) | game over |
| `OfferDraw` / `AcceptDraw` / `DeclineDraw` | `DrawOffered`, `GameEnded`, `DrawDeclined` | no open offer, own offer |
| `ClaimTimeout` | `GameEnded` (timeout) | opponent still has time |
| `ClaimDraw` | `GameEnded` (repetition or fifty-move) | condition not met |

**Aggregate state:** a map of node id to node (parent, move, board, side to move, castling rights, en passant square, halfmove clock, clocks, status), the children of each node, and any open draw offer. Repetition counts are computed along a node's own ancestry.

**Event payload tip:** put SAN, the resulting FEN and the clock timestamps in `MoveMade`. Read models and replay then never need to re-run the rules.

**Other aggregates to consider:** `Player` (profile, rating), `Challenge` or `Lobby` (matchmaking), `Tournament`. Keep them separate from `Game` so a game's stream stays small and fast.

## Rules engine

Keep chess rules in a pure Elixir module with no Commanded dependency, so the aggregate only calls it and it can be tested alone.

- **API sketch:** `Rules.legal_moves(position)`, `Rules.apply_move(position, move)` returning `{:ok, position, flags}` or `{:error, reason}`, and `Rules.outcome(position, history)`.
- **Board representation:** a map of square to piece is simplest to read; bitboards are faster but only matter if you add an engine. Decide now, since it is costly to change later.
- **Ambiguity:** accept moves as from/to/promotion; generate SAN on the way out.
- **Draws:** track position hashes (Zobrist or FEN-without-counters) for threefold repetition; halfmove clock for the fifty-move rule; insufficient material check. Count repetitions and the halfmove clock along the path from the root to a node, never across the whole tree.
- **Or buy instead of build:** check existing Hex packages for move generation before writing your own; verify their maintenance status first.

**Testing**

- Perft tests (known node counts from the start position and the standard tricky positions) catch almost every move-generation bug.
- Property tests with StreamData: any legal move sequence never leaves the mover's king in check.
- Replay real PGN games and assert the final FEN.

## Time controls and process managers

Aggregates must stay deterministic, so time enters as data on the command, never read inside `execute/2`.

- **Clock model:** store the remaining time per side and the timestamp of the move on every node. How clocks behave across branches is an open question (see Branching model). The server stamps `MakeMove` with the receive time, so clients cannot forge it. Add an increment or delay if you support Fischer or Bronstein controls.
- **Timeouts:** a process manager starts on `GameStarted`, schedules a timer for the side to move, and reschedules on each `MoveMade`. When it fires it dispatches `ClaimTimeout`, which the aggregate validates against the stored clock. Commanded has no built-in timer, so use `Process.send_after` in a supervised process or an Oban job.
- **Restart safety:** timers vanish on restart. On boot, rebuild them from a read model of active games.
- **Draw offers:** keep in the aggregate. An offer expires when the offerer moves.
- **Matchmaking:** a `Lobby` process manager pairs `ChallengeCreated` events and dispatches `StartGame`.
- **Abandonment:** a disconnect timer that claims a win after N seconds is a common house rule; decide whether to include it.

## Read models and real-time UI

Project events into Postgres with `commanded_ecto_projections`, and push the same events to browsers through Phoenix PubSub.

| Read model | Fed by | Used for |
| --- | --- | --- |
| `games` (current FEN, status, clocks) | `GameStarted`, `MoveMade`, `GameEnded` | game page, active games list |
| `nodes` (node id, parent id, ply, SAN, FEN, mover) | `MoveMade` | branch overview, move list, replay |
| `player_stats` (rating, W/D/L) | `GameEnded` | profiles, leaderboards |
| `active_timers` | `GameStarted`, `MoveMade`, `GameEnded` | rebuilding timers on restart |

- **UI:** Phoenix LiveView with a JS board hook (chessboard.js or a custom SVG) keeps state server-side. Players submit moves as commands and the board updates when the projection broadcasts.
- **Spectators:** subscribe to the game's PubSub topic. No extra write path is needed.
- **Eventual consistency:** after `dispatch` returns, the read model may lag. Use `consistency: :strong` on the command for the mover's own view, or update the UI optimistically and reconcile on the broadcast.
- **Rebuilds:** projections can be reset and replayed from the store, so read-model schema changes are cheap.

## Event store concerns

Getting the event shapes right early matters most, because stored events are permanent.

- **Stream design:** one stream per game, so the stream grows with every branch; cap branches per game if needed. Snapshots are not needed for `Game`; long-lived aggregates such as `Player` may need them.
- **Event versioning:** use Commanded upcasters (`Commanded.Event.Upcaster`) to migrate old payloads at read time instead of rewriting history.
- **Serialization:** JSON is easy to inspect. Use a custom serializer with explicit type names so renaming a module does not break stored events.
- **Metadata:** record `correlation_id`, `causation_id` and the acting user id on every command. Anti-cheat and audit both rely on it.
- **Idempotency:** supply a command `uuid` from the client so a retried `MakeMove` is not applied twice.
- **Replay and export:** PGN export (branches written as PGN variations) is a fold over `MoveMade` events. Replay is a read of the stream, with no engine involved.
- **Privacy:** if you store IPs or emails in events, plan for deletion requests up front (crypto-shredding or keep PII out of events).

## Ideas to explore

Event sourcing makes several features cheap that are hard in a CRUD design.

- **Time-travel replay:** step through any game, or share a link to a specific ply.
- **Opening explorer:** project all `MoveMade` events into a move-tree read model showing win rates by position.
- **Engine analysis as a side stream:** an event handler sends finished games to Stockfish and emits `GameAnalysed` with accuracy scores and blunders.
- **Anti-cheat signals:** a projection comparing move times and engine agreement per player, flagging outliers for review.
- **Tournaments:** a `Tournament` aggregate with a process manager that pairs rounds (Swiss or round robin) from `GameEnded` events.
- **Puzzles from real games:** mine positions where the played move differed sharply from the engine's best.
- **Correspondence chess:** days-per-move clocks fit the same model, with timers backed by Oban.
- **Variants:** Chess960 and others change only the rules module and the starting position in `GameStarted`.
- **Bots:** a bot is just another client that dispatches `MakeMove`.
- **Spectator features:** delayed broadcast for streamers, live commentary, and public game embeds.

## Risks, open questions and build order

The biggest risks are rules bugs and clock handling, so build and test both before any UI.

**Risks**

- Move-generation bugs that surface only in rare positions (mitigated by perft tests).
- Clock drift and network lag making timeouts feel unfair.
- Event shapes that need changing after launch (mitigated by upcasters and by putting derived data such as SAN and FEN in events now).
- Read-model lag causing a stale board. Loose rules on who may branch, and when, would let a player undo a losing move.

**Open questions**

- Rules engine: write your own or use an existing library?
- Accounts required, or guest play?
- Single node or clustered at launch?
- Which time controls ship in the MVP, and how do clocks work across branches?

**Suggested build order**

1. Rules module with perft and property tests.
2. `Game` aggregate as a tree of nodes, router and commands, tested with in-memory events.
3. EventStore setup and a CLI or IEx session that plays a full game.
4. `games` and `moves` projections.
5. LiveView board for two players, then the branch overview.
6. Clocks and the timeout process manager.
7. Draw offers, resignation and repetition claims.
8. Accounts, lobby, ratings.
9. Spectators, replay and PGN export.
