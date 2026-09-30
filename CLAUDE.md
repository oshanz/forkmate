# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` holds the Phoenix 1.8 / LiveView / Ecto / HEEx / Elixir / test conventions for this repo. Follow it; it is not repeated here.

## Commands

- `bin/dev` — start Postgres (docker compose), run `mix setup`, then `iex -S mix phx.server`
- `mix test test/path_test.exs:LINE` — a single test; `mix test --failed` — rerun failures
- `mix precommit` — run when finished: compile with warnings as errors, format, `credo --strict`, test

## Architecture

Forkmate is an online chess game built as CQRS/event sourcing on Phoenix (Commanded, EventStore, `commanded_ecto_projections`). The design in `docs/design-brainstorm.md` is still a proposal; read it before adding domain code. No aggregates, commands, events or projections exist yet.

Key design decisions from that doc:
- One `Game` aggregate per game; the stream ID is the game ID, and all rule checks happen in the aggregate.
- A game is a **tree of positions**, not a line. `MakeMove` carries `from_node_id`; if that node already has a child, a branch is created and `BranchCreated` is also emitted. Rewinding is client-side only and writes no events. Only the player whose colour is to move at a node may branch from it.
- `MoveMade` carries SAN, the resulting FEN and clock timestamps, so read models and replay never re-run the rules.
- Read models (e.g. a `nodes` table) are Ecto projections. The branch overview is rendered as SVG in LiveView.
- `Player`, `Challenge`/`Lobby` and `Tournament` are separate aggregates from `Game`.

### Two Postgres databases

- `Forkmate.Repo` (Ecto) holds read models and projections.
- `Forkmate.EventStore` (`lib/forkmate/event_store.ex`) is a separate database. In prod it uses `EVENTSTORE_DATABASE_URL` (falls back to `DATABASE_URL`) and `EVENTSTORE_POOL_SIZE`.
- `Forkmate.Application` starts the event store only when `:start_event_store` is true. `config/test.exs` sets it to `false`, so tests that need it must start it themselves.
- `mix ecto.setup` (and so `mix setup`) also runs `event_store.create` and `event_store.init`; `ecto.reset` runs `event_store.drop`. Both are idempotent.

### Web layer and design system

- Standard Phoenix 1.8 layout under `lib/forkmate_web/`; only the default `PageController` exists so far. Tailwind has two profiles, `forkmate` and `storybook`.
- UI is developed in Phoenix Storybook at `/storybook` (content in `storybook/`; `game/*` has one story per component, `design/*` has architecture and game-screen pages).
- `ForkmateWeb.GameComponents` holds the presentational chess components (board from FEN, move list, clock, branch graph, etc.). They only render data passed in and never run chess rules. When changing one, update its story in `storybook/game/`.
