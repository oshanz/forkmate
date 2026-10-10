# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` holds the Phoenix 1.8 / LiveView / Ecto / HEEx / Elixir / test conventions for this repo. Follow it; it is not repeated here.

## Commands

- `mise install` — install the pinned toolchain and Stockfish (the computer opponent; tests tagged `:stockfish` are skipped without it)
- `bin/dev` — start Postgres (docker compose), run `mix setup`, then `iex -S mix phx.server`
- `mix phx.server` — run the Phoenix server directly
- `mix test test/path_test.exs:LINE` — a single test; `mix test --failed` — rerun failures
- `mix precommit` — run when finished: compile with warnings as errors, `deps.unlock --unused`, format, `credo --strict`, test. It runs in the `:test` env and can modify `mix.lock`, so check `git diff mix.lock` afterwards.
- `mix precommit` also runs `cargo clippy` and `cargo test` for the NIF crate (Rust 1.97+).
- `mix test` first runs `ecto.create` and `ecto.migrate` for the test DB, so Postgres must be running (`docker compose up -d`) even if you don't use `bin/dev`.
- Toolchain versions come from `mise.toml`: latest Elixir and Erlang, Rust 1.97 and Stockfish `sf_19`.

## Architecture

Forkmate is an online chess game built using CQRS and event sourcing on Phoenix (`Commanded`, `EventStore`, `commanded_ecto_projections`).
See `docs/design-brainstorm.md` for background and future roadmap items (`Player`, `Challenge`/`Lobby`, `Tournament`).
The README's status line and Architecture section say the domain code doesn't exist yet. That is outdated; trust the code and this file.

### Core Domain & CQRS (`lib/forkmate/`)

- **Chess rules** (`lib/forkmate/chess/`): `Position`, `Piece`, `Square`, `Move` are pure data types (FEN parsing/formatting, UCI). Rules are accessed only through the `Forkmate.Chess.Engine` behaviour, selected by `config :forkmate, :chess_engine` (only implementation: `Engine.Shakmaty`, a Rustler NIF over the `shakmaty` crate in `native/forkmate_chess`). `shakmaty` is GPL-3.0-or-later. Threefold repetition is computed in Elixir (shakmaty has no history). `Forkmate.Chess.Native` is the raw NIF: FEN/UCI strings only.
- **Bots** (`lib/forkmate/bots/`): a bot is a player id `bot:stockfish:<level>` (`Bots.Seat`; levels easy/medium/hard/max). `Bots.Player` is a Commanded event handler (`start_from: :current`) that plays for bot seats through ordinary `MakeMove` commands, in tasks under `Forkmate.Bots.TaskSupervisor`; it waits for the game's read-model row first. `Bots.Stockfish` (a pool of UCI Port workers) implements the `Bots.Bot` behaviour, selected by `config :forkmate, :bot` (`Bots.FakeBot` in tests). Stockfish comes from `mise install` or `STOCKFISH_PATH`; tests tagged `:stockfish` are skipped when it is absent. In bot games `GameLive` locks the perspective to the human's colour.
- **Game aggregate** (`lib/forkmate/games/game.ex`): One `Game` aggregate per game; the stream ID is the game ID. Maintains a **tree of positions** (`nodes` map) rather than a linear move list:
  - `MakeMove` carries `from_node_id`; if that node already has children, a new branch is created and both `BranchCreated` and `MoveMade` are emitted.
  - Rewinding is client-side only and writes no events.
  - Only the player whose colour is to move at a node may play or branch from it.
  - Commands: `StartGame`, `MakeMove`, `OfferDraw`, `AcceptDraw`, `DeclineDraw`, `Resign`.
  - Events: `GameStarted`, `MoveMade`, `BranchCreated`, `DrawOffered`, `DrawDeclined`, `GameEnded`. `MoveMade` carries SAN, resulting FEN, and clock timestamps so projections and replay never re-evaluate chess rules.
- **Commanded app & routing**:
  - `Forkmate.CommandedApp` (`lib/forkmate/commanded_app.ex`) uses `Commanded.Application` and manages `Forkmate.EventStore`.
  - `Forkmate.Games.Router` (`lib/forkmate/games/router.ex`) routes commands to `Forkmate.Games.Game`.
- **Read models & Projections**:
  - `Forkmate.Games.ReadModels.Game` and `Forkmate.Games.ReadModels.Node` (`lib/forkmate/games/read_models/`).
  - `Forkmate.Games.Projections.GameProjection` (`lib/forkmate/games/projections/game_projection.ex`) uses `Commanded.Projections.Ecto` with `:strong` consistency, writes to Postgres tables `games` and `game_nodes`, and broadcasts updates over `Forkmate.PubSub`.
- **Games Context** (`lib/forkmate/games.ex`): Public API for dispatching commands (with `:strong` consistency) and querying game read models.

### Two Postgres Databases & Supervision

- `Forkmate.Repo` (Ecto) holds read models and projections (`forkmate_dev` / `forkmate_test`).
- `Forkmate.EventStore` (`lib/forkmate/event_store.ex`) is a separate database (`forkmate_eventstore_dev` / `forkmate_eventstore_test`). In prod it uses `EVENTSTORE_DATABASE_URL` (falls back to `DATABASE_URL`) and `EVENTSTORE_POOL_SIZE`.
- **Supervision tree**:
  - `Forkmate.CommandedApp` configures `Commanded.EventStore.Adapters.EventStore`, which internally starts and supervises `Forkmate.EventStore`.
  - `Forkmate.Application` supervises `[Forkmate.CommandedApp, Forkmate.Games.Projections.GameProjection, Task.Supervisor (Forkmate.Bots.TaskSupervisor), Forkmate.Bots.Stockfish.Pool, Forkmate.Bots.Player]` via `event_store_children()` when `:start_event_store` is true. `Forkmate.EventStore` must **not** be listed separately as a sibling child in `Forkmate.Application`.
  - In `config/test.exs`, `:start_event_store` is false. Tests that require Commanded and projections start them explicitly via `start_supervised!(Forkmate.CommandedApp)` and `start_supervised!(Forkmate.Games.Projections.GameProjection)`. The test event store persists between runs while the read-model database is rolled back, so any new event handler must tolerate replayed events for games with no read model (if the projection crash-loops on a foreign key error, reset it with `MIX_ENV=test mix event_store.drop && create && init`).
- `mix ecto.setup` (and `mix setup`) also runs `event_store.create` and `event_store.init`, then `priv/repo/seeds.exs`; `ecto.reset` runs `event_store.drop`. Both are idempotent.
- `mix assets.build` compiles two Tailwind profiles (`forkmate` and `storybook`) plus esbuild.
- Tests mirror `lib/` under `test/forkmate` and `test/forkmate_web`; shared helpers (`ConnCase`, `DataCase`) are in `test/support`.

### Web Layer & UI

- Phoenix 1.8 layout under `lib/forkmate_web/`:
  - `ForkmateWeb.PageController` (`/`): Home page with a start-new-game button and the play-vs-computer form (`POST /games`; `mode=bot` with `level` and `color` starts a bot game).
  - `ForkmateWeb.GameLive` (`/games/:id`): Interactive chess interface with real-time board rendering, move highlights, branching tree navigation, move list, draw offers, resignations, and game status. Subscribes to `game:<id>` on `Forkmate.PubSub`.
- UI components and Storybook:
  - Developed in Phoenix Storybook at `/storybook` (`storybook/game/` for component stories, `storybook/design/` for architecture and screens).
  - Architecture diagrams in Storybook use Mermaid (`<div phx-hook="Mermaid" phx-update="ignore">`). Keep diagrams small and top-to-bottom.
  - Storybook pages outside the `forkmate` sandbox follow the OS `prefers-color-scheme`; put `data-theme="light"` on a story's root element if needed.
  - `ForkmateWeb.GameComponents` holds presentational chess components (board from FEN, move list, clock, branch graph, etc.). They only render data passed in and never run chess rules. When modifying them, update corresponding stories in `storybook/game/`.
