# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` holds the Phoenix 1.8 / LiveView / Ecto / HEEx / Elixir / test conventions for this repo. Follow it; it is not repeated here.

## Commands

- `bin/dev` — start Postgres (docker compose), run `mix setup`, then `iex -S mix phx.server`
- `mix phx.server` — run the Phoenix server directly
- `mix test test/path_test.exs:LINE` — a single test; `mix test --failed` — rerun failures
- `mix precommit` — run when finished: compile with warnings as errors, format, `credo --strict`, test

## Architecture

Forkmate is an online chess game built using CQRS and event sourcing on Phoenix (`Commanded`, `EventStore`, `commanded_ecto_projections`).
See `docs/design-brainstorm.md` for background and future roadmap items (`Player`, `Challenge`/`Lobby`, `Tournament`).

### Core Domain & CQRS (`lib/forkmate/`)

- **Chess rules engine** (`lib/forkmate/chess/`): Pure functional chess engine (`Position`, `Piece`, `Square`, `Move`, `Rules`). Handles legal move generation/validation, FEN parsing/formatting, SAN notation, check/checkmate/stalemate, castling, en passant, pawn promotion, and draw conditions (insufficient material, 50-move rule, threefold repetition).
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
  - `Forkmate.Application` supervises `[Forkmate.CommandedApp, Forkmate.Games.Projections.GameProjection]` via `event_store_children()` when `:start_event_store` is true. `Forkmate.EventStore` must **not** be listed separately as a sibling child in `Forkmate.Application`.
  - In `config/test.exs`, `:start_event_store` is false. Tests that require Commanded and projections start them explicitly via `start_supervised!(Forkmate.CommandedApp)` and `start_supervised!(Forkmate.Games.Projections.GameProjection)`.
- `mix ecto.setup` (and `mix setup`) also runs `event_store.create` and `event_store.init`; `ecto.reset` runs `event_store.drop`. Both are idempotent.

### Web Layer & UI

- Phoenix 1.8 layout under `lib/forkmate_web/`:
  - `ForkmateWeb.PageController` (`/`): Home page showing active/recent games and a quick button to start a new game (`POST /games`).
  - `ForkmateWeb.GameLive` (`/games/:id`): Interactive chess interface with real-time board rendering, move highlights, branching tree navigation, move list, draw offers, resignations, and game status. Subscribes to `game:<id>` on `Forkmate.PubSub`.
- UI components and Storybook:
  - Developed in Phoenix Storybook at `/storybook` (`storybook/game/` for component stories, `storybook/design/` for architecture and screens).
  - Architecture diagrams in Storybook use Mermaid (`<div phx-hook="Mermaid" phx-update="ignore">`). Keep diagrams small and top-to-bottom.
  - Storybook pages outside the `forkmate` sandbox follow the OS `prefers-color-scheme`; put `data-theme="light"` on a story's root element if needed.
  - `ForkmateWeb.GameComponents` holds presentational chess components (board from FEN, move list, clock, branch graph, etc.). They only render data passed in and never run chess rules. When modifying them, update corresponding stories in `storybook/game/`.
