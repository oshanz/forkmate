# Replace the in-repo rules engine with shakmaty

Date: 2026-10-10
Status: implemented (Rules module retained as oracle; removal deferred)

## Goal

Stop maintaining our own chess rules engine (`lib/forkmate/chess/`, about 1,200 lines) and rely on the well-tested `shakmaty` Rust crate, wrapped in a NIF with Rustler. Standard chess only. Fewer lines of rules code and higher confidence in correctness are the aims. Variants, bots, and analysis are not goals of this work.

## Context

- Rules are used in two places:
  - the `Game` aggregate (`Rules.apply_move`, `Rules.check_square`, `Rules.outcome`, `Position.from_fen`)
  - the `Games` context (`Rules.legal_moves`, which backs move highlighting and move validation in the LiveView)
- Events (`MoveMade`, etc.) store SAN, resulting FEN and clock data. Projections and replay never re-run the rules, so event history is independent of the engine.
- `Rules.perft` already exists.
- `shakmaty` 0.30.2 is `GPL-3.0-or-later` (verified on crates.io). The licence was confirmed acceptable for Forkmate.
- `shakmaty` declares a minimum Rust version of 1.97. The local toolchain is `cargo` 1.92 and must be upgraded.
- The repo has no Dockerfile, CI config, or release setup yet.

## Non-goals

- Chess variants, bot players, Stockfish integration.
- Any change to events, projections, the position tree, or the UI components.
- `rustler_precompiled` (revisit when real CI and releases exist).

## Design

### 1. Staging and boundary

**Stage A, oracle (test-only).**
- Add `rustler` and a crate at `native/forkmate_chess` wrapping `shakmaty`.
- Expose functions for: legal moves for a FEN, apply a move (resulting FEN and SAN), and outcome.
- Add differential tests comparing it with the current engine.
- Nothing in `lib/` calls the NIF yet.

**Stage B, swap, only if Stage A passes.**
- Add a `Forkmate.Chess.Engine` behaviour covering `legal_moves`, `apply_move` (new FEN, SAN, check square, outcome) and FEN validation.
- `Game` and `Games` call the behaviour. The implementation is selected by config, with the shakmaty implementation as the default.
- Delete the old rules code once the suite is green.

**Boundary.** FEN and UCI strings go in; plain maps come out. Events, projections, the tree and the UI keep using the `Position` fields they need.

### 2. Errors, build and deploy

**Errors.**
- The NIF returns `{:ok, result}` or `{:error, reason}`, with `reason` one of `:invalid_fen`, `:illegal_move`, `:invalid_uci`. The behaviour maps these to the errors `Game` already returns, so commands and the LiveView see no change.
- The Rust side never uses `unwrap` on input; all parsing goes through `Result`, because a panic in a NIF can crash the whole VM.
- FENs are validated by `shakmaty` before they can reach an event.
- Existing events keep their stored FEN and SAN. Replay never calls the engine, so engine differences cannot corrupt history. Only newly played moves are affected.

**Build.**
- `mise.toml` gets `rust = "1.97"` (or newer).
- Rustler compiles the crate during `mix compile`. `Cargo.lock` is checked in.
- `mix precommit` gains `cargo clippy` and `cargo test` steps, so one command checks everything. The cost is a slower precommit.
- The first Rust compile is slow; later compiles are incremental.

**Deploy (future).**
- Any Docker image or CI job needs Rust 1.97 or newer at build time. The compiled `.so` ships in the release; nothing needs Rust at runtime.

### 3. Testing and migration

**Stage A tests.**
- Perft suite: the standard positions (start position, Kiwipete, and the en passant and promotion-heavy positions from the Chess Programming Wiki) at modest depths. Both engines must match the published node counts, not just each other.
- Random games: a few thousand seeded games, comparing both engines at every ply on legal move set, resulting FEN, SAN, check square and outcome (including draw conditions).
- Any disagreement fails the test and prints the FEN, the move and each engine's answer. A disagreement where our engine is wrong is a real bug found.
- Tests are tagged `:differential` so slow ones can be excluded locally but still run in `precommit`.

**Gate between A and B.** Swap only with zero unexplained differences. Known benign differences, such as SAN disambiguation style, are either normalised in the tests or documented here, never silently ignored.

**Stage B steps.**
1. Introduce the `Engine` behaviour with the current engine as the first implementation. Move `Game` and `Games` onto it. No behaviour changes, and the existing tests pass unchanged.
2. Add the shakmaty implementation and switch the config default.
3. Run the full suite (aggregate and LiveView tests included) against the new default.
4. Delete the old rules code, keeping `Position` only where the UI still needs it. Removal may wait a couple of releases, so rollback stays a one-line config change until then.

## Risks

- NIF crash takes down the VM. Mitigated by `Result`-only parsing and the differential suite.
- Toolchain friction: Rust 1.97 is needed on every dev machine and in future CI.
- GPL-3.0-or-later applies to the combined work if Forkmate is distributed.
- SAN or outcome differences between engines for newly played moves. Mitigated by Stage A normalisation and the gate.
