# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` holds the Phoenix 1.8 / LiveView / Ecto / HEEx / Elixir / test conventions for this repo. Follow it; it is not repeated here.

## Commands

- `mix setup` — deps, create/migrate DBs, seeds, build assets
- `mix phx.server` (or `iex -S mix phx.server`) — run at localhost:4000
- `mix test` — the alias creates and migrates the test DB first
- `mix test test/path_test.exs:LINE` — a single test; `mix test --failed` — rerun failures
- `mix precommit` — run when finished: `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `credo --strict`, `test` (runs in the `:test` env)

## Architecture

Forkmate is an online chess game built as CQRS/event sourcing on Phoenix, using Commanded, `commanded_eventstore_adapter`, `commanded_ecto_projections` and `EventStore` (Postgres). The design is in `docs/design-brainstorm.md` and is still a proposal. Read it before adding domain code. The scaffolding (Phoenix app, event store wiring) exists, but no aggregates, commands, events or projections have been written yet.

Key design decisions from that doc:
- One `Game` aggregate per game; the stream ID is the game ID, and all rule checks happen in the aggregate.
- A game is a **tree of positions**, not a line. `MakeMove` carries `from_node_id`; if that node already has a child, a branch is created and `BranchCreated` is also emitted. Rewinding is client-side only and writes no events. Only the player whose colour is to move at a node may branch from it.
- Put SAN, the resulting FEN and clock timestamps in `MoveMade` so read models and replay never re-run the rules.
- Read models (e.g. a `nodes` table) are Ecto projections. The branch overview is rendered as SVG in LiveView.
- Keep `Player`, `Challenge`/`Lobby` and `Tournament` as separate aggregates from `Game`.

### Two Postgres databases

- `Forkmate.Repo` (Ecto) holds read models and projections.
- `Forkmate.EventStore` (`lib/forkmate/event_store.ex`) is a separate database, e.g. `forkmate_eventstore_dev` and `forkmate_eventstore_test`. In prod it uses `EVENTSTORE_DATABASE_URL`, which falls back to the main `DATABASE_URL`, and `EVENTSTORE_POOL_SIZE`. It is registered under `event_stores:` in `config/config.exs`.
- `Forkmate.Application` starts the event store only when `:start_event_store` is true. `config/test.exs` sets it to `false`, so tests that need the event store must start it themselves.
- No `mix event_store.*` aliases are defined in `mix.exs`. Check `mix help | grep event_store` before assuming the store's schema has been initialised.

### Web layer

Standard Phoenix 1.8 layout under `lib/forkmate_web/`. Only the default `PageController` home page exists so far. `phoenix_live_dashboard` and `eventstore_dashboard` are dependencies for inspecting streams. Assets use esbuild and tailwind (`mix assets.build`, `mix assets.deploy`).
