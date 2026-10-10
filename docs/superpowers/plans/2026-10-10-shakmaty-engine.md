# Shakmaty Rules Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Route all chess rules through a Rustler NIF wrapping `shakmaty`, behind a swappable `Forkmate.Chess.Engine` behaviour, with the old engine kept as a test oracle.

**Architecture:** A small Rust crate (`native/forkmate_chess`) exposes three string-in/tuple-out NIFs (`legal_moves`, `apply_move`, `outcome`). Differential tests compare it with the existing `Rules` module (Stage A). A `Forkmate.Chess.Engine` behaviour with two implementations (`Engine.Elixir` = current `Rules`, `Engine.Shakmaty` = NIF) is selected by config; `Game` and `Games` call the behaviour (Stage B). `Position`, `Move`, `Square`, `Piece` stay as Elixir data types.

**Tech Stack:** Elixir/Phoenix, Commanded, Rustler 0.38, Rust 1.97+, `shakmaty` 0.30.2 (GPL-3.0-or-later).

**Spec:** `docs/superpowers/specs/2026-10-10-shakmaty-engine-design.md`

## Global Constraints

- Standard chess only. No variants, no bot, no Stockfish.
- Rust toolchain: 1.97 or newer (`shakmaty` 0.30.2 declares `rust-version = 1.97`; local cargo was 1.92).
- NIF errors are `{:error, :invalid_fen | :illegal_move | :invalid_uci}`; the NIF never panics on input and never uses `unwrap` on input-derived values.
- Events, projections, the position tree and UI components are not changed. Stored FEN and SAN stay as-is; replay never calls the engine.
- Rust crate lives in `native/forkmate_chess` with `Cargo.lock` checked in.
- Commit messages carry no AI attribution (user's global rule).
- `mix precommit` must pass at the end of every task that changes Elixir code.
- The old `Rules` module is NOT deleted in this plan (spec: removal may wait; rollback stays a one-line config change). Deletion is a follow-up decision.

## Review Focus

- En passant square in FEN output: must match our convention (and standard FEN: set after every double push), i.e. `EnPassantMode::Always`, not `Legal`. Test: FEN after `e2e4` contains `e3`.
- Promotion: UCI with a promotion letter (`a7a8q`) parses, applies, and `legal_moves` lists all four promotion choices. SAN is `a8=Q`.
- Castling UCI is king-to-destination (`e1g1`), never king-takes-rook (`e1h1`).
- FENs `shakmaty` considers impossible (no kings, side not to move in check): `Engine.validate/1` rejects them, so `StartGame` with such an `initial_fen` returns `{:error, {:invalid_fen, _}}` instead of crashing later.
- Threefold repetition: `shakmaty` has no history, so `Engine.Shakmaty.outcome/2` computes it in Elixir from the position history. Test: a knight-shuffle sequence yields `:threefold_repetition` on the third occurrence.
- Garbage input to the NIF (`""`, `"nonsense"`, 10 KB string, `"e2e4e5"`) returns an error tuple, never raises or crashes the VM.

---

### Task 1: Toolchain, crate scaffold, `legal_moves` NIF

**Files:**
- Modify: `mise.toml`, `mix.exs`, `.gitignore`
- Create: `native/forkmate_chess/Cargo.toml`, `native/forkmate_chess/src/lib.rs`
- Create: `lib/forkmate/chess/native.ex`
- Test: `test/forkmate/chess/native_test.exs`

**Interfaces:**
- Produces: `Forkmate.Chess.Native.legal_moves(fen :: String.t()) :: {:ok, [uci :: String.t()]} | {:error, :invalid_fen}`

- [ ] **Step 1: Upgrade the toolchain**

Edit `mise.toml` so it reads:

```toml
[tools]
elixir = "latest"
erlang = "latest"
rust = "1.97"
```

Run: `mise install && cargo --version`
Expected: `cargo 1.97.x` or newer. If `1.97` is not yet installable, use the newest stable that satisfies `shakmaty`'s declared `rust-version` (re-check with `curl -s https://crates.io/api/v1/crates/shakmaty -H 'User-Agent: forkmate' | python3 -I -c "import sys,json;print(json.load(sys.stdin)['versions'][0]['rust_version'])"`) and use that in `mise.toml` and the crate's `rust-version`.

- [ ] **Step 2: Add rustler and gitignore entries**

In `mix.exs` `deps/0`, add after the `credo` line (add a comma to the credo line):

```elixir
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:rustler, "~> 0.38.0", runtime: false}
```

Append to `.gitignore`:

```
# Rust build output.
/native/forkmate_chess/target/
/priv/native/
```

Run: `mix deps.get`
Expected: rustler fetched, `mix.lock` updated.

- [ ] **Step 3: Write the failing test**

Create `test/forkmate/chess/native_test.exs`:

```elixir
defmodule Forkmate.Chess.NativeTest do
  use ExUnit.Case, async: true

  alias Forkmate.Chess.{Native, Position}

  describe "legal_moves/1" do
    test "start position has 20 moves in UCI form" do
      assert {:ok, moves} = Native.legal_moves(Position.start_fen())
      assert length(moves) == 20
      assert "e2e4" in moves
      assert "g1f3" in moves
    end

    test "castling is king-to-destination" do
      assert {:ok, moves} = Native.legal_moves("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
      assert "e1g1" in moves
      assert "e1c1" in moves
      refute "e1h1" in moves
    end

    test "promotion lists all four choices" do
      assert {:ok, moves} = Native.legal_moves("8/P6k/8/8/8/8/8/K7 w - - 0 1")
      assert Enum.sort(Enum.filter(moves, &String.starts_with?(&1, "a7a8"))) ==
               ["a7a8b", "a7a8n", "a7a8q", "a7a8r"]
    end

    test "garbage input returns an error tuple" do
      for bad <- ["", "nonsense", String.duplicate("x", 10_000)] do
        assert {:error, :invalid_fen} = Native.legal_moves(bad)
      end
    end

    test "kingless position is rejected" do
      assert {:error, :invalid_fen} = Native.legal_moves("8/8/8/8/8/8/8/8 w - - 0 1")
    end
  end
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `mix test test/forkmate/chess/native_test.exs`
Expected: FAIL/compile error, `Forkmate.Chess.Native` is undefined.

- [ ] **Step 5: Create the crate**

`native/forkmate_chess/Cargo.toml`:

```toml
[package]
name = "forkmate_chess"
version = "0.1.0"
edition = "2021"
rust-version = "1.97"
license = "GPL-3.0-or-later"

[lib]
name = "forkmate_chess"
crate-type = ["cdylib"]

[dependencies]
rustler = "0.38"
shakmaty = "=0.30.2"
```

`native/forkmate_chess/src/lib.rs`:

```rust
use rustler::Atom;
use shakmaty::{fen::Fen, uci::UciMove, CastlingMode, Chess, Position};

mod atoms {
    rustler::atoms! {
        invalid_fen,
        illegal_move,
        invalid_uci,
    }
}

fn parse_position(fen: &str) -> Result<Chess, Atom> {
    let fen: Fen = fen.parse().map_err(|_| atoms::invalid_fen())?;
    fen.into_position(CastlingMode::Standard)
        .map_err(|_| atoms::invalid_fen())
}

#[rustler::nif]
fn legal_moves(fen: &str) -> Result<Vec<String>, Atom> {
    let pos = parse_position(fen)?;
    Ok(pos
        .legal_moves()
        .iter()
        .map(|m| UciMove::from_standard(*m).to_string())
        .collect())
}

rustler::init!("Elixir.Forkmate.Chess.Native");
```

> `shakmaty` 0.30's exact method names (`UciMove::from_standard`, `Fen::into_position`) may differ slightly from the above. The Elixir contract in the tests is fixed; if `cargo build` reports an API mismatch, consult `cargo doc -p shakmaty --open` or docs.rs/shakmaty/0.30.2 and adapt the Rust only.

- [ ] **Step 6: Create the Elixir NIF module**

`lib/forkmate/chess/native.ex`:

```elixir
defmodule Forkmate.Chess.Native do
  @moduledoc """
  Rustler NIF wrapping the `shakmaty` chess crate (GPL-3.0-or-later).

  All functions take and return plain strings: FEN in, UCI moves out. Errors are
  `{:error, :invalid_fen | :illegal_move | :invalid_uci}`.
  """

  use Rustler, otp_app: :forkmate, crate: "forkmate_chess", path: "native/forkmate_chess"

  @spec legal_moves(String.t()) :: {:ok, [String.t()]} | {:error, :invalid_fen}
  def legal_moves(_fen), do: :erlang.nif_error(:nif_not_loaded)
end
```

- [ ] **Step 7: Run test to verify it passes**

Run: `mix test test/forkmate/chess/native_test.exs`
Expected: PASS (first run compiles Rust, which takes a while).

- [ ] **Step 8: Run precommit and commit**

Run: `mix precommit && git diff mix.lock`
Expected: passes. `mix.lock` shows only the rustler addition (plus its deps).

```bash
git add mise.toml mix.exs mix.lock .gitignore native lib/forkmate/chess/native.ex test/forkmate/chess/native_test.exs
git commit -m "feat(chess): add shakmaty NIF scaffold with legal_moves"
```

---

### Task 2: `apply_move` and `outcome` NIFs

**Files:**
- Modify: `native/forkmate_chess/src/lib.rs`, `lib/forkmate/chess/native.ex`
- Test: `test/forkmate/chess/native_test.exs`

**Interfaces:**
- Consumes: Task 1 crate and module.
- Produces:
  - `Native.apply_move(fen, uci) :: {:ok, {new_fen :: String.t(), san :: String.t(), outcome :: String.t(), check_square :: String.t() | nil}} | {:error, :invalid_fen | :invalid_uci | :illegal_move}`
  - `Native.outcome(fen) :: {:ok, String.t()} | {:error, :invalid_fen}`
  - `outcome` strings: `"ongoing" | "checkmate" | "stalemate" | "insufficient_material" | "fifty_move"` (repetition is not computed here).

- [ ] **Step 1: Write the failing tests**

Append inside `NativeTest` (before the final `end`):

```elixir
  describe "apply_move/2" do
    test "scholar's mate: SAN has #, outcome checkmate, check square" do
      fen = "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4"

      assert {:ok, {new_fen, "Qxf7#", "checkmate", "e8"}} = Native.apply_move(fen, "h5f7")
      assert new_fen == "r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4"
    end

    test "double pawn push sets the en passant square (EnPassantMode::Always)" do
      assert {:ok, {fen, "e4", "ongoing", nil}} =
               Native.apply_move(Position.start_fen(), "e2e4")

      assert fen == "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"
    end

    test "en passant capture" do
      fen = "rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3"

      assert {:ok, {new_fen, "exf6", "ongoing", nil}} = Native.apply_move(fen, "e5f6")
      assert new_fen == "rnbqkbnr/ppp1p1pp/5P2/3p4/8/8/PPPP1PPP/RNBQKBNR b KQkq - 0 3"
    end

    test "castling" do
      fen = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"

      assert {:ok, {new_fen, "O-O", "ongoing", nil}} = Native.apply_move(fen, "e1g1")
      assert new_fen == "r3k2r/8/8/8/8/8/8/R4RK1 b kq - 1 1"
    end

    test "promotion" do
      fen = "8/P6k/8/8/8/8/8/K7 w - - 0 1"

      assert {:ok, {new_fen, "a8=Q", "ongoing", nil}} = Native.apply_move(fen, "a7a8q")
      assert new_fen == "Q7/7k/8/8/8/8/8/K7 b - - 0 1"
    end

    test "move that causes stalemate" do
      # White Qg6 leaves the king on h8 with no moves and not in check.
      fen = "7k/8/5K2/8/8/8/8/6Q1 w - - 0 1"

      assert {:ok, {_fen, "Qg6", "stalemate", nil}} = Native.apply_move(fen, "g1g6")
    end

    test "errors" do
      assert {:error, :illegal_move} = Native.apply_move(Position.start_fen(), "e2e5")
      assert {:error, :invalid_uci} = Native.apply_move(Position.start_fen(), "zz")
      assert {:error, :invalid_uci} = Native.apply_move(Position.start_fen(), "e2e4e5")
      assert {:error, :invalid_fen} = Native.apply_move("nonsense", "e2e4")
    end
  end

  describe "outcome/1" do
    test "classifies terminal and ongoing positions" do
      assert {:ok, "ongoing"} = Native.outcome(Position.start_fen())
      assert {:ok, "checkmate"} =
               Native.outcome("r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4")
      assert {:ok, "stalemate"} = Native.outcome("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
      assert {:ok, "insufficient_material"} = Native.outcome("4k3/8/8/8/8/8/8/4K3 w - - 0 1")
      assert {:ok, "fifty_move"} = Native.outcome("4k3/8/8/8/8/8/8/R3K3 w - - 100 80")
      assert {:error, :invalid_fen} = Native.outcome("nonsense")
    end
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/forkmate/chess/native_test.exs`
Expected: FAIL, `apply_move/2` and `outcome/1` are undefined.

- [ ] **Step 3: Implement in Rust**

In `native/forkmate_chess/src/lib.rs`, change the `use shakmaty` line to:

```rust
use shakmaty::{
    fen::Fen, san::SanPlus, uci::UciMove, CastlingMode, Chess, EnPassantMode, Position,
};
```

Add above `rustler::init!`:

```rust
fn outcome_label(pos: &Chess) -> &'static str {
    if pos.is_checkmate() {
        "checkmate"
    } else if pos.is_stalemate() {
        "stalemate"
    } else if pos.is_insufficient_material() {
        "insufficient_material"
    } else if pos.halfmoves() >= 100 {
        "fifty_move"
    } else {
        "ongoing"
    }
}

fn check_square(pos: &Chess) -> Option<String> {
    if pos.is_check() {
        pos.board().king_of(pos.turn()).map(|sq| sq.to_string())
    } else {
        None
    }
}

#[rustler::nif]
fn apply_move(
    fen: &str,
    uci: &str,
) -> Result<(String, String, String, Option<String>), Atom> {
    let pos = parse_position(fen)?;
    let uci: UciMove = uci.parse().map_err(|_| atoms::invalid_uci())?;
    let mv = uci.to_move(&pos).map_err(|_| atoms::illegal_move())?;

    let san = SanPlus::from_move(pos.clone(), mv).to_string();
    let next = pos.play(mv).map_err(|_| atoms::illegal_move())?;

    Ok((
        Fen::from_position(next.clone(), EnPassantMode::Always).to_string(),
        san,
        outcome_label(&next).to_string(),
        check_square(&next),
    ))
}

#[rustler::nif]
fn outcome(fen: &str) -> Result<String, Atom> {
    let pos = parse_position(fen)?;
    Ok(outcome_label(&pos).to_string())
}
```

(Same API caveat as Task 1: adapt method names to `shakmaty` 0.30.2 if `cargo build` complains; keep the Elixir-facing contract.)

- [ ] **Step 4: Add the Elixir stubs**

In `lib/forkmate/chess/native.ex`, add after `legal_moves/1`:

```elixir
  @spec apply_move(String.t(), String.t()) ::
          {:ok, {String.t(), String.t(), String.t(), String.t() | nil}}
          | {:error, :invalid_fen | :invalid_uci | :illegal_move}
  def apply_move(_fen, _uci), do: :erlang.nif_error(:nif_not_loaded)

  @spec outcome(String.t()) :: {:ok, String.t()} | {:error, :invalid_fen}
  def outcome(_fen), do: :erlang.nif_error(:nif_not_loaded)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/forkmate/chess/native_test.exs`
Expected: PASS. If a hand-written FEN or SAN expectation fails because the test data itself is wrong (not the NIF), confirm against a second source (the old `Rules`, via `iex -S mix`) before changing the expectation, and note it in the commit message.

- [ ] **Step 6: Precommit and commit**

Run: `mix precommit`
Expected: passes.

```bash
git add native lib/forkmate/chess/native.ex test/forkmate/chess/native_test.exs
git commit -m "feat(chess): add apply_move and outcome NIFs"
```

---

### Task 3: Differential tests (Stage A gate)

**Files:**
- Create: `test/forkmate/chess/differential_test.exs`
- Modify: `test/test_helper.exs` (only if it excludes tags; see Step 1)
- Modify: `docs/superpowers/specs/2026-10-10-shakmaty-engine-design.md` (record any accepted differences)

**Interfaces:**
- Consumes: `Native.legal_moves/1`, `Native.apply_move/2`, `Rules.legal_moves/1`, `Rules.apply_move/2`, `Rules.check_square/1`, `Move.to_uci/1`, `Position.to_fen/1`.

- [ ] **Step 1: Check the test helper**

Run: `cat test/test_helper.exs`
Expected: no tag exclusions. Do not exclude `:differential` by default; `precommit` must run it (spec).

- [ ] **Step 2: Write the differential tests**

`test/forkmate/chess/differential_test.exs`:

```elixir
defmodule Forkmate.Chess.DifferentialTest do
  @moduledoc """
  Compares the in-repo `Rules` engine with the shakmaty NIF. Both must match
  published perft counts, and agree on every ply of seeded random games.
  """
  use ExUnit.Case, async: true

  alias Forkmate.Chess.{Move, Native, Position, Rules}

  @moduletag :differential

  @perft [
    {"start", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", [{1, 20}, {2, 400}, {3, 8_902}]},
    {"kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
     [{1, 48}, {2, 2_039}]},
    {"position 3", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [{1, 14}, {2, 191}, {3, 2_812}]},
    {"position 4", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
     [{1, 6}, {2, 264}]},
    {"position 5", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
     [{1, 44}, {2, 1_486}]}
  ]

  for {name, fen, counts} <- @perft, {depth, expected} <- counts do
    test "native perft #{name} depth #{depth} matches published count" do
      assert native_perft(unquote(fen), unquote(depth)) == unquote(expected)
    end
  end

  @games 300
  @max_plies 200

  for seed <- 1..@games do
    test "random game #{seed}: engines agree on every ply" do
      play(unquote(seed))
    end
  end

  # --- helpers ---

  defp native_perft(fen, 1) do
    {:ok, moves} = Native.legal_moves(fen)
    length(moves)
  end

  defp native_perft(fen, depth) do
    {:ok, moves} = Native.legal_moves(fen)

    Enum.reduce(moves, 0, fn uci, acc ->
      {:ok, {next_fen, _san, _outcome, _check}} = Native.apply_move(fen, uci)
      acc + native_perft(next_fen, depth - 1)
    end)
  end

  defp play(seed) do
    :rand.seed(:exsss, {seed, seed * 7, seed * 13})
    step(Position.start(), 1, [])
  end

  defp step(_pos, ply, _trail) when ply > @max_plies, do: :ok

  defp step(pos, ply, trail) do
    fen = Position.to_fen(pos)
    old_moves = Rules.legal_moves(pos)
    {:ok, native_moves} = Native.legal_moves(fen)

    assert Enum.sort(Enum.map(old_moves, &Move.to_uci/1)) == Enum.sort(native_moves),
           context("legal moves differ", fen, nil, trail)

    if old_moves == [] do
      :ok
    else
      move = Enum.random(old_moves)
      uci = Move.to_uci(move)
      {:ok, next, meta} = Rules.apply_move(pos, move)
      {:ok, {native_fen, native_san, native_outcome, native_check}} = Native.apply_move(fen, uci)

      ctx = context("apply differs", fen, uci, trail)
      assert Position.to_fen(next) == native_fen, ctx
      assert meta.san == native_san, ctx
      assert outcome_label(meta.outcome) == native_outcome, ctx
      assert Rules.check_square(next) == native_check, ctx

      if meta.outcome == :ongoing, do: step(next, ply + 1, [uci | trail]), else: :ok
    end
  end

  defp outcome_label({:checkmate, _winner}), do: "checkmate"
  defp outcome_label(atom) when is_atom(atom), do: Atom.to_string(atom)

  defp context(msg, fen, uci, trail) do
    "#{msg}: fen=#{fen} move=#{inspect(uci)} trail(last first)=#{inspect(Enum.take(trail, 10))}"
  end
end
```

- [ ] **Step 3: Run the suite**

Run: `mix test test/forkmate/chess/differential_test.exs`
Expected: either PASS, or failures that print the FEN, move and trail of the first disagreement.

- [ ] **Step 4: Triage every failure (the gate)**

For each distinct failure class, decide which engine is wrong, by checking the position against the FEN/SAN standard (and a third source such as the published perft counts or an independent board editor):
- Our engine is wrong: add a regression test to `test/forkmate/chess/rules_test.exs` reproducing it; this is a real bug found. Fix `rules.ex` only if the fix is small; otherwise record it in the spec and let the shakmaty result stand as correct.
- Pure formatting difference (for example SAN disambiguation style): normalise in the test with a small, commented helper, and record the rule in the spec's "Known differences" list (add the section if it does not exist).
- shakmaty is wrong or the NIF glue is wrong: fix `lib.rs`.

Gate: Task 4 may only start with zero unexplained differences. Re-run the whole file until green.

Note on terminal-outcome ordering: our engine reports `:insufficient_material` / `:fifty_move` only when the move list is non-empty; both engines check mate and stalemate first, so they should agree. If they disagree on insufficient material (our rule set is narrower than shakmaty's), prefer shakmaty's FIDE definition, update `rules.ex` only if trivial, otherwise normalise in the test and record it.

- [ ] **Step 5: Precommit and commit**

Run: `mix precommit`
Expected: passes (the differential file now runs in `mix test`).

```bash
git add test/forkmate/chess/differential_test.exs docs/superpowers/specs/2026-10-10-shakmaty-engine-design.md test/forkmate/chess/rules_test.exs lib/forkmate/chess/rules.ex
git commit -m "test(chess): add differential suite comparing Rules with shakmaty NIF"
```

(Only `git add` files that actually changed.)

---

### Task 4: `Engine` behaviour with the current engine; move callers onto it

**Files:**
- Create: `lib/forkmate/chess/engine.ex`, `lib/forkmate/chess/engine/elixir.ex`
- Modify: `lib/forkmate/games/game.ex`, `lib/forkmate/games.ex`
- Test: `test/forkmate/chess/engine_test.exs`

**Interfaces:**
- Produces `Forkmate.Chess.Engine` behaviour and facade, all `Position.t()` based:
  - `legal_moves(Position.t()) :: [Move.t()]`
  - `apply_move(Position.t(), Move.t()) :: {:ok, Position.t(), meta :: map()} | {:error, term()}` (meta keys: `san, from, to, promotion, captured_piece, is_check, is_checkmate, outcome`)
  - `check_square(Position.t()) :: Square.name() | nil`
  - `outcome(Position.t(), [Position.t()]) :: :ongoing | {:checkmate, Piece.color()} | :stalemate | :insufficient_material | :fifty_move | :threefold_repetition`
  - `validate(Position.t()) :: :ok | {:error, term()}`
  - `Engine.impl/0` reads `Application.get_env(:forkmate, :chess_engine, Forkmate.Chess.Engine.Elixir)`.

- [ ] **Step 1: Write the failing test**

`test/forkmate/chess/engine_test.exs`:

```elixir
defmodule Forkmate.Chess.EngineTest do
  use ExUnit.Case, async: true

  alias Forkmate.Chess.{Engine, Move, Position}

  for impl <- [Forkmate.Chess.Engine.Elixir, Forkmate.Chess.Engine.Shakmaty] do
    describe "#{inspect(impl)}" do
      @impl_mod impl

      test "legal_moves/1" do
        assert length(@impl_mod.legal_moves(Position.start())) == 20
      end

      test "apply_move/2 returns position and meta" do
        move = Move.new("e2", "e4")
        assert {:ok, %Position{active_color: :black}, meta} = @impl_mod.apply_move(Position.start(), move)
        assert meta.san == "e4"
        assert meta.outcome == :ongoing
        assert meta.is_check == false
        assert meta.is_checkmate == false
      end

      test "apply_move/2 rejects illegal moves" do
        assert {:error, :illegal_move} =
                 @impl_mod.apply_move(Position.start(), Move.new("e2", "e5"))
      end

      test "check_square/1" do
        pos = Position.from_fen!("r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4")
        assert @impl_mod.check_square(pos) == "e8"
        assert @impl_mod.check_square(Position.start()) == nil
      end

      test "outcome/2 reports checkmate winner" do
        pos = Position.from_fen!("r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4")
        assert @impl_mod.outcome(pos, []) == {:checkmate, :white}
      end

      test "outcome/2 detects threefold repetition from history" do
        start = Position.start()
        shuffle = ["g1f3", "g8f6", "f3g1", "f6g8"]

        positions =
          Enum.scan(shuffle ++ shuffle, start, fn uci, pos ->
            {:ok, move} = Move.from_uci(uci)
            {:ok, next, _meta} = @impl_mod.apply_move(pos, move)
            next
          end)

        # After two full shuffles the start position has occurred 3 times (initial + 2 returns).
        current = List.last(positions)
        history = [start | Enum.drop(Enum.reverse(positions), 1)]
        assert @impl_mod.outcome(current, history) == :threefold_repetition
      end

      test "validate/1 accepts a normal position" do
        assert @impl_mod.validate(Position.start()) == :ok
      end
    end
  end

  describe "facade" do
    test "delegates to the configured implementation" do
      assert length(Engine.legal_moves(Position.start())) == 20
    end
  end
end
```

(The Shakmaty module is created in Task 5, so tests for it fail until then. To keep Task 4 green on its own, temporarily guard the loop: change `for impl <- [..., Forkmate.Chess.Engine.Shakmaty]` to list only `Forkmate.Chess.Engine.Elixir` in this task, and add `Forkmate.Chess.Engine.Shakmaty` back in Task 5, Step 1.)

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/forkmate/chess/engine_test.exs`
Expected: FAIL, `Forkmate.Chess.Engine` / `Engine.Elixir` undefined.

- [ ] **Step 3: Create the behaviour and facade**

`lib/forkmate/chess/engine.ex`:

```elixir
defmodule Forkmate.Chess.Engine do
  @moduledoc """
  Behaviour and facade for the chess rules authority.

  The implementation is chosen with `config :forkmate, :chess_engine, Module`.
  `Forkmate.Chess.Engine.Elixir` wraps the in-repo `Rules` module;
  `Forkmate.Chess.Engine.Shakmaty` uses the shakmaty NIF.
  """

  alias Forkmate.Chess.{Move, Piece, Position, Square}

  @type outcome ::
          :ongoing
          | {:checkmate, Piece.color()}
          | :stalemate
          | :insufficient_material
          | :fifty_move
          | :threefold_repetition

  @callback legal_moves(Position.t()) :: [Move.t()]
  @callback apply_move(Position.t(), Move.t()) :: {:ok, Position.t(), map()} | {:error, term()}
  @callback check_square(Position.t()) :: Square.name() | nil
  @callback outcome(Position.t(), [Position.t()]) :: outcome()
  @callback validate(Position.t()) :: :ok | {:error, term()}

  @spec impl() :: module()
  def impl, do: Application.get_env(:forkmate, :chess_engine, __MODULE__.Elixir)

  def legal_moves(pos), do: impl().legal_moves(pos)
  def apply_move(pos, move), do: impl().apply_move(pos, move)
  def check_square(pos), do: impl().check_square(pos)
  def outcome(pos, history \\ []), do: impl().outcome(pos, history)
  def validate(pos), do: impl().validate(pos)
end
```

`lib/forkmate/chess/engine/elixir.ex`:

```elixir
defmodule Forkmate.Chess.Engine.Elixir do
  @moduledoc "Engine implementation backed by the in-repo `Forkmate.Chess.Rules`."

  @behaviour Forkmate.Chess.Engine

  alias Forkmate.Chess.Rules

  @impl true
  defdelegate legal_moves(pos), to: Rules

  @impl true
  defdelegate apply_move(pos, move), to: Rules

  @impl true
  defdelegate check_square(pos), to: Rules

  @impl true
  def outcome(pos, history), do: Rules.outcome(pos, history)

  @impl true
  def validate(_pos), do: :ok
end
```

- [ ] **Step 4: Move callers onto the facade**

`lib/forkmate/games/game.ex`:
- Line 10: `alias Forkmate.Chess.{Move, Position, Rules}` becomes `alias Forkmate.Chess.{Engine, Move, Position}`.
- `Rules.apply_move(parent_node.position, move)` becomes `Engine.apply_move(parent_node.position, move)`.
- `check: Rules.check_square(next_position),` becomes `check: Engine.check_square(next_position),`.
- `if Rules.outcome(next_position, history) == :threefold_repetition do` becomes `if Engine.outcome(next_position, history) == :threefold_repetition do`.
- Replace the `StartGame` handler's `case` with a `with` that also validates the position:

```elixir
    with {:ok, pos} <- Position.from_fen(initial_fen),
         :ok <- Engine.validate(pos) do
      {:ok,
       [
         %GameStarted{
           game_id: cmd.game_id,
           root_node_id: root_node_id,
           white_player_id: cmd.white_player_id,
           black_player_id: cmd.black_player_id,
           initial_fen: initial_fen
         }
       ]}
    else
      {:error, reason} -> {:error, {:invalid_fen, reason}}
    end
```

`lib/forkmate/games.ex`:
- Line 9: `alias Forkmate.Chess.{Position, Rules, Square}` becomes `alias Forkmate.Chess.{Engine, Position, Square}`.
- Replace the three `Rules.legal_moves(` occurrences (in `legal_targets/2`, `promotion_targets/2`, `promotion_move?/3`) with `Engine.legal_moves(`.

- [ ] **Step 5: Run the full suite**

Run: `mix test`
Expected: PASS, with no change in behaviour (default engine is still the old one).

- [ ] **Step 6: Precommit and commit**

Run: `mix precommit`
Expected: passes (credo reports no unused aliases).

```bash
git add lib/forkmate/chess/engine.ex lib/forkmate/chess/engine lib/forkmate/games/game.ex lib/forkmate/games.ex test/forkmate/chess/engine_test.exs
git commit -m "refactor(chess): route rules calls through an Engine behaviour"
```

---

### Task 5: `Engine.Shakmaty` and the config switch

**Files:**
- Create: `lib/forkmate/chess/engine/shakmaty.ex`
- Modify: `config/config.exs`, `test/forkmate/chess/engine_test.exs`
- Test: `test/forkmate/games/game_test.exs`

**Interfaces:**
- Consumes: `Native.*` (Tasks 1-2), `Engine` behaviour (Task 4).
- Produces: `Forkmate.Chess.Engine.Shakmaty` implementing all five callbacks; default engine config set to it.

- [ ] **Step 1: Re-enable Shakmaty in the engine tests and add pins**

In `test/forkmate/chess/engine_test.exs`, change the loop back to:

```elixir
  for impl <- [Forkmate.Chess.Engine.Elixir, Forkmate.Chess.Engine.Shakmaty] do
```

Add this describe block at the end of the module:

```elixir
  describe "Engine.Shakmaty validation" do
    alias Forkmate.Chess.Engine.Shakmaty

    test "rejects kingless positions" do
      pos = Position.from_fen!("8/8/8/8/8/8/8/8 w - - 0 1")
      assert {:error, :invalid_fen} = Shakmaty.validate(pos)
    end

    test "legal_moves is empty for a rejected position instead of raising" do
      pos = Position.from_fen!("8/8/8/8/8/8/8/8 w - - 0 1")
      assert Shakmaty.legal_moves(pos) == []
    end
  end
```

Add to `test/forkmate/games/game_test.exs`, inside the module's StartGame tests (find them with `grep -n "StartGame" test/forkmate/games/game_test.exs` and follow the neighbouring setup/style):

```elixir
    test "StartGame with a kingless initial_fen is rejected" do
      cmd = %StartGame{
        game_id: Ecto.UUID.generate(),
        white_player_id: "w",
        black_player_id: "b",
        initial_fen: "8/8/8/8/8/8/8/8 w - - 0 1"
      }

      assert {:error, {:invalid_fen, _}} =
               Game.execute(%Game{}, cmd)
    end
```

(If that file builds the aggregate state differently, mirror its existing helper, but keep the assertion `{:error, {:invalid_fen, _}}`. The test must run with the Shakmaty engine; set it per-test with `Application.put_env(:forkmate, :chess_engine, Forkmate.Chess.Engine.Shakmaty)` and restore via `on_exit` unless the default is already switched in Step 5.)

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/forkmate/chess/engine_test.exs`
Expected: FAIL, `Forkmate.Chess.Engine.Shakmaty` undefined.

- [ ] **Step 3: Add the `check_square_of` NIF**

Add a test to `test/forkmate/chess/native_test.exs`:

```elixir
  describe "check_square_of/1" do
    test "reports the checked king's square" do
      assert {:ok, "e8"} =
               Native.check_square_of("r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 0 4")

      assert {:ok, nil} = Native.check_square_of(Position.start_fen())
    end
  end
```

In `native/forkmate_chess/src/lib.rs` add above `rustler::init!`:

```rust
#[rustler::nif]
fn check_square_of(fen: &str) -> Result<Option<String>, Atom> {
    let pos = parse_position(fen)?;
    Ok(check_square(&pos))
}
```

In `lib/forkmate/chess/native.ex` add:

```elixir
  @spec check_square_of(String.t()) :: {:ok, String.t() | nil} | {:error, :invalid_fen}
  def check_square_of(_fen), do: :erlang.nif_error(:nif_not_loaded)
```

Run: `mix test test/forkmate/chess/native_test.exs`
Expected: PASS.

- [ ] **Step 4: Implement the module**

`lib/forkmate/chess/engine/shakmaty.ex`:

```elixir
defmodule Forkmate.Chess.Engine.Shakmaty do
  @moduledoc """
  Engine implementation backed by the shakmaty NIF (`Forkmate.Chess.Native`).

  Repetition detection stays in Elixir because shakmaty positions carry no history.
  """

  @behaviour Forkmate.Chess.Engine

  alias Forkmate.Chess.{Move, Native, Piece, Position, Square}

  @impl true
  def legal_moves(%Position{} = pos) do
    case Native.legal_moves(Position.to_fen(pos)) do
      {:ok, ucis} -> Enum.flat_map(ucis, &parse_uci/1)
      {:error, _reason} -> []
    end
  end

  @impl true
  def apply_move(%Position{} = pos, %Move{} = move) do
    uci = Move.to_uci(move)

    case Native.apply_move(Position.to_fen(pos), uci) do
      {:ok, {fen, san, outcome, check_square}} ->
        next = Position.from_fen!(fen)
        {:ok, next, meta(pos, move, next, san, outcome, check_square)}

      {:error, :invalid_uci} ->
        {:error, :illegal_move}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def check_square(%Position{} = pos) do
    case Native.check_square_of(Position.to_fen(pos)) do
      {:ok, square} -> square
      {:error, _reason} -> nil
    end
  end

  @impl true
  def outcome(%Position{} = pos, history) do
    case Native.outcome(Position.to_fen(pos)) do
      {:ok, "checkmate"} -> {:checkmate, Piece.opponent(pos.active_color)}
      {:ok, "stalemate"} -> :stalemate
      {:ok, "insufficient_material"} -> :insufficient_material
      {:ok, "fifty_move"} -> :fifty_move
      {:ok, "ongoing"} -> if repetition?(pos, history), do: :threefold_repetition, else: :ongoing
      {:error, _} -> :ongoing
    end
  end

  @impl true
  def validate(%Position{} = pos) do
    case Native.legal_moves(Position.to_fen(pos)) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # --- helpers ---

  defp parse_uci(uci) do
    case Move.from_uci(uci) do
      {:ok, move} -> [move]
      :error -> []
    end
  end

  defp meta(pos, move, next, san, outcome, check_square) do
    is_check = check_square != nil

    %{
      san: san,
      from: Square.to_name(move.from),
      to: Square.to_name(move.to),
      promotion: move.promotion,
      captured_piece: Map.get(pos.board, move.to),
      is_check: is_check,
      is_checkmate: outcome == "checkmate",
      outcome: outcome_term(outcome, pos.active_color, next)
    }
  end

  defp outcome_term("checkmate", mover, _next), do: {:checkmate, mover}
  defp outcome_term("stalemate", _mover, _next), do: :stalemate
  defp outcome_term("insufficient_material", _mover, _next), do: :insufficient_material
  defp outcome_term("fifty_move", _mover, _next), do: :fifty_move
  defp outcome_term("ongoing", _mover, _next), do: :ongoing

  defp repetition?(pos, history) do
    key = position_key(pos)
    Enum.count([pos | history], &(position_key(&1) == key)) >= 3
  end

  defp position_key(%Position{} = p), do: {p.board, p.active_color, p.castling, p.en_passant}
end
```

- [ ] **Step 5: Switch the default**

In `config/config.exs`, add after the `config :forkmate, event_stores: ...` block:

```elixir
config :forkmate, :chess_engine, Forkmate.Chess.Engine.Shakmaty
```

- [ ] **Step 6: Run the whole suite on the new default**

Run: `mix test`
Expected: PASS: aggregate tests, LiveView tests, `Games` tests, differential tests (which still use `Rules` directly as the oracle), and the new pins.
If an existing test fails only because of an FEN or SAN formatting difference, treat it as a missed Stage A difference: add a differential case reproducing it, triage as in Task 3 Step 4, then fix.

- [ ] **Step 7: Verify rollback is one line**

Temporarily set `config :forkmate, :chess_engine, Forkmate.Chess.Engine.Elixir`, run `mix test`, expect PASS, then restore the Shakmaty line. (Do not commit the temporary change.)

- [ ] **Step 8: Precommit and commit**

Run: `mix precommit`
Expected: passes.

```bash
git add lib/forkmate/chess/engine/shakmaty.ex lib/forkmate/chess/native.ex native config/config.exs test
git commit -m "feat(chess): add shakmaty-backed Engine and make it the default"
```

---

### Task 6: Precommit integration and docs

**Files:**
- Modify: `mix.exs`, `CLAUDE.md`, `README.md` (only if it mentions the toolchain), spec status line

- [ ] **Step 1: Add Rust checks to precommit**

In `mix.exs` `aliases/0`, change `precommit` to:

```elixir
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "cmd cargo clippy --manifest-path native/forkmate_chess/Cargo.toml -- -D warnings",
        "cmd cargo test --manifest-path native/forkmate_chess/Cargo.toml",
        "test"
      ]
```

Run: `mix precommit`
Expected: passes. If clippy reports warnings in `lib.rs`, fix them in the Rust code (no `#[allow]` unless justified in a comment).

- [ ] **Step 2: Update CLAUDE.md**

In the "Core Domain & CQRS" section, replace the chess rules engine bullet with:

```markdown
- **Chess rules** (`lib/forkmate/chess/`): `Position`, `Piece`, `Square`, `Move` are pure data types. Rules are accessed only through the `Forkmate.Chess.Engine` behaviour, selected by `config :forkmate, :chess_engine` (default `Engine.Shakmaty`, a Rustler NIF over the `shakmaty` crate in `native/forkmate_chess`; `Engine.Elixir` wraps the legacy `Rules` module, kept as a differential-test oracle and rollback path). Threefold repetition is computed in Elixir (shakmaty has no history). `Forkmate.Chess.Native` is the raw NIF: FEN/UCI strings only.
```

In the Commands section add: `- Rust 1.97+ is required (pinned in mise.toml); \`mix precommit\` also runs \`cargo clippy\` and \`cargo test\` for the NIF. shakmaty is GPL-3.0-or-later.`

- [ ] **Step 3: Mark the spec**

Change the spec's `Status:` line to `implemented (Rules module retained as oracle; removal deferred)`.

- [ ] **Step 4: Final verification and commit**

Run: `mix precommit && git status --short`
Expected: precommit passes; only the intended files are modified.

```bash
git add mix.exs CLAUDE.md docs/superpowers/specs/2026-10-10-shakmaty-engine-design.md
git commit -m "chore: run NIF clippy and tests in precommit, document the engine"
```

## Self-review notes

- Spec coverage: Stage A (Tasks 1-3), Engine behaviour and swap (Tasks 4-5), error handling and no-panic parsing (Tasks 1-2, Review Focus), build/toolchain/precommit (Tasks 1, 6), perft and random-game gate (Task 3), rollback (Task 5 Step 7), deletion of old code deferred as the spec allows (Global Constraints).
- Deviation recorded from the spec: `Position`, `Move`, `Square`, `Piece` are kept because the aggregate state and UI use them; only `Rules` becomes legacy. The `validate/1` callback was added so `StartGame` rejects positions shakmaty cannot represent.
