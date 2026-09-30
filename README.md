# Forkmate

An online chess game where every game is an append-only event stream, and any game can be **forked**: rewind to an earlier position, play a different move, and see every branch of the game in one overview.

> Status: early. The Phoenix app and event store wiring are in place; the chess domain is still being designed. See [`docs/design-brainstorm.md`](docs/design-brainstorm.md).

## The game

**MVP**

- Two players play a full, rules-correct game: all legal moves, castling, en passant and promotion.
- A game ends by checkmate, stalemate, resignation, agreed draw, threefold repetition, the fifty-move rule or timeout.
- Live board for both players, game history and replay.
- Rewind to any earlier position and play a different move to start a branch. Every branch is drawn in a git-style graph.

**Branching**

A game is a tree of positions, not a line. Rewinding is client-side and writes nothing. Playing a move from an earlier position appends an event, and if that position already has a continuation it becomes a new branch. Only the player whose colour is to move at a position may branch from it.

**Later:** matchmaking and lobbies, Elo ratings, tournaments, engine analysis, anti-cheat signals, variants such as Chess960.

## Tech

- **Elixir / Phoenix 1.8** with **LiveView** for the real-time board and branch overview
- **Commanded** (CQRS/ES) with **EventStore** on Postgres for the event log
- **commanded_ecto_projections** and **Ecto** for read models
- **Postgres**, with two databases: one for read models and one for the event store
- **Tailwind CSS v4** and **esbuild** for assets, **Bandit** as the web server
- **Credo** (strict) for linting

## Getting started

Requires Elixir 1.15+ and a running Postgres.

```sh
mix setup          # deps, databases, migrations, seeds, assets
mix phx.server     # or: iex -S mix phx.server
```

Then visit [localhost:4000](http://localhost:4000).

In production, the event store reads `EVENTSTORE_DATABASE_URL` (falling back to `DATABASE_URL`) and `EVENTSTORE_POOL_SIZE`.

## Development

```sh
mix test                       # runs against a test database
mix test path/to/file_test.exs # a single file
mix precommit                  # compile (warnings as errors), format, credo --strict, test
```

Run `mix precommit` before committing.
