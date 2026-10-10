# Play vs Computer (Stockfish bot)

## Goal

Let a user start a game against a computer opponent from the home page, choosing
the difficulty and their colour. The bot is a seat in the game, moves on the
server, and keeps working if the browser closes or reloads.

## Scope

In scope:
- "Play vs computer" option on the home page: difficulty + colour (White, Black, Random).
- A Stockfish-backed bot that replies to the human's moves.
- Dev/CI provisioning of the Stockfish binary.

Out of scope (v1):
- Bot resigning, offering or accepting draws (the bot always declines).
- Bot vs bot, analysis, hints, engine-evaluation display.
- Production packaging of Stockfish (the repo has no Dockerfile yet).
- Chess rule changes. Rules stay behind `Forkmate.Chess.Engine`.

## Design

### Bot seat

The bot is one of the two existing player-id strings, so the `Game` aggregate,
commands and events do not change.

- Bot id format: `bot:stockfish:<level>` (e.g. `bot:stockfish:medium`).
- The human keeps `"Player 1"` as today.
- `Forkmate.Bots.Seat` (pure helpers): `bot?/1`, `level/1`, `label/1`
  (`"Stockfish (Medium)"` for display), `new/1`, `human_color/2`.

Difficulty levels are named presets of Stockfish options (Stockfish 17's
`UCI_Elo` cannot go below 1320, so Easy uses `Skill Level` instead):

| Level | Stockfish options | Move time |
|---|---|---|
| Easy | `UCI_LimitStrength=false`, `Skill Level=0` | 50 ms |
| Medium | `UCI_LimitStrength=true`, `UCI_Elo=1400` | 300 ms |
| Hard | `UCI_LimitStrength=true`, `UCI_Elo=2000` | 600 ms |
| Max | `UCI_LimitStrength=false`, `Skill Level=20` | 1000 ms |

Every request sets all of these options, so a pooled process never inherits
another game's strength. The values are tuned by feel during implementation.

### Components

- `Forkmate.Bots.Bot` — behaviour: `best_move(fen, level) :: {:ok, uci_string} | {:error, term}` and `available?/0`.
- `Forkmate.Bots.Stockfish` — implements `Bot`. Talks UCI to Stockfish through an
  Erlang Port. A small supervised pool of long-lived Stockfish processes; each
  request does `setoption` (strength), `position fen <fen>`, `go movetime <ms>`,
  and reads until `bestmove`. Requests are stateless, so any pooled process can
  serve any game. Configurable: binary path (`STOCKFISH_PATH`, default
  `stockfish` on `PATH`), pool size, move time.
- `Forkmate.Bots.Player` — Commanded event handler. Subscribes to `GameStarted`,
  `MoveMade` and `DrawOffered` (see Draw offers). If the side to move at the new node is a bot seat, it calls the
  configured `Bot`, converts the UCI move with `Forkmate.Chess.Move`, and
  dispatches `Games.make_move/1` with the bot's `player_id` and the new node as
  `from_node_id`. It ignores ended games.
- Config: `config :forkmate, :bot, Forkmate.Bots.Stockfish` so tests can swap in a fake.
- `Forkmate.Application` adds the Stockfish pool and the handler to the same
  `event_store_children()` group as the projection, so they start only when the
  event store starts (not in the default test env).

### Web

- Home page: a "Play vs computer" form beside the existing "New game" button,
  with a difficulty select (Easy/Medium/Hard/Max) and a colour select
  (White/Black/Random). It POSTs to `/games` with `mode=bot`, `level`, `color`.
- `PageController.create_game/2`: for `mode=bot`, validate `level` and `color`
  against allowlists, resolve Random once on the server, and assign the seats.
  Refuse to create the game (flash "Computer opponent unavailable", redirect to `/`)
  if the bot is not available (see error handling). Without `mode=bot` behaviour
  is unchanged.
- `GameLive` today lets one browser play both colours (`?as=` and a flip
  button). In a bot game the perspective is locked to the human's colour: `?as=`
  is ignored, the flip button is hidden and `switch_perspective` is a no-op, so
  the human can never send a move or resign as the bot.
- `GameLive` shows `Seat.label/1` for bot seats and a "thinking…" indicator
  while it is the bot's turn in an ongoing game (derived from game state). Draw
  offers to the bot are declined by the server and the human sees the existing
  decline state.

### Data flow

1. Controller → `Games.start_game/1` with the two seat ids.
2. Projection writes the read model and broadcasts (unchanged).
3. `Bots.Player` receives `GameStarted`; if White is the bot, it moves.
4. Human moves → `MoveMade` → `Bots.Player` replies → projection broadcasts → board updates.
5. Repeat until `GameEnded`.

Branching: when the human rewinds and plays a different move from one of their
own nodes, the resulting `MoveMade` triggers a bot reply from that new node like
any other. The aggregate already prevents the human from moving on the bot's turn.

### Draw offers

When the human offers a draw to a bot seat, `Bots.Player` handles `DrawOffered`
and dispatches `DeclineDraw` as the bot.

### Error handling

- Availability check: `Bots.Stockfish.available?/0` (the binary resolves from
  `STOCKFISH_PATH` or `PATH` and exists). Used by the controller before creating a bot game.
- Bot call fails or times out mid-game: retry once, then log and stop. The game
  stays playable (the human can resign or abandon it). v1 shows no separate
  failure notice in the UI.
- Bot returns an illegal move: the aggregate rejects `MakeMove`; the handler logs
  and does not retry the same move.
- The bot's reply uses a node id derived from the node it replies to, so a
  duplicate event delivery fails with `:node_id_taken` and cannot double-move.
  The handler subscribes with `start_from: :current`, and the actual Stockfish
  call runs in a supervised task so a slow search never blocks event handling.
- Stockfish process crash: the pool restarts it.

### Provisioning

- Dev/CI via mise, using the `github` backend (no `stockfish` entry exists in the
  mise registry), pinned to a release in `mise.toml`.
- Asset choice must not hard-code a CPU-specific build. First try mise's automatic
  platform asset matching; if that picks wrong or fails, pin the portable baseline
  per platform (`x86-64` for Intel/AMD, `apple-silicon` for Macs).
- Verification step in the implementation plan: confirm `mise install` yields a
  working `stockfish` on the developer's machine before building on it. If the
  `github:` backend does not work, fall back to a pinned download script that
  checks a SHA-256 and unpacks into `priv/stockfish/`.
- Stockfish is GPL-3.0, compatible with this project (GPL-3.0-or-later via
  shakmaty). Add a README note crediting Stockfish with a source link.
- Production packaging is deferred until a deploy setup exists.

### Testing

- `Bots.Seat`: unit tests for parsing, labels, levels.
- `Bots.Stockfish`: UCI response parsing unit tests (`bestmove`, `info` lines, errors).
- `Bots.Player` with a fake `Bot` (via config): bot moves first as White; replies
  after a human move; no reply after `GameEnded`; replies from a new branch;
  declines a draw; ignores human-vs-human games; does not double-move on replay.
  These start `CommandedApp` and `GameProjection` explicitly, as the existing
  tests do.
- `PageController`: bot game with each level and colour, Random resolves to a
  valid colour, invalid level or colour rejected, unavailable bot gives the flash
  and no game, non-bot path unchanged.
- `GameLive`: bot seat label, thinking indicator on the bot's turn.
- One integration test against real Stockfish, tagged `:stockfish` and excluded
  when the binary is absent.
- Update `GameComponents` stories only if a presentational component changes.
- `mix precommit` must pass.

## Open points to resolve during implementation

- Exact mise `github:` asset pattern for each platform (verify, see Provisioning).
- Move time per level (start with 500 ms Easy to 1500 ms Max, tune by feel).
- Whether the "thinking…" indicator needs a PubSub signal or can be derived from
  game state (prefer derived).
