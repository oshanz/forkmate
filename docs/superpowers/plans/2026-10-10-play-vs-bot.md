# Play vs Computer (Stockfish bot) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user start a game against a Stockfish bot from the home page, choosing difficulty and colour.

**Architecture:** The bot is a seat id (`bot:stockfish:<level>`) in the existing `Game` aggregate, so no aggregate changes. A Commanded event handler (`Bots.Player`) reacts to `GameStarted`, `MoveMade` and `DrawOffered`, asks a `Bot` implementation for a move in a supervised task, and dispatches a normal `MakeMove`. `Bots.Stockfish` drives a small pool of long-lived Stockfish UCI ports. `GameLive` locks the perspective to the human's colour in bot games.

**Tech Stack:** Elixir, Phoenix 1.8 LiveView, Commanded 1.4, Erlang Ports (UCI), Stockfish, mise.

**Spec:** `docs/superpowers/specs/2026-10-10-play-vs-bot-design.md`

## Global Constraints

- Follow `AGENTS.md` conventions. Run `mix precommit` at the end; check `git diff mix.lock` afterwards.
- Rules stay behind `Forkmate.Chess.Engine`; do not add chess rules.
- Do not change the `Game` aggregate, commands or events.
- `Forkmate.Application`: bot children go inside `event_store_children()` (started only when `:start_event_store` is true). Do not list `Forkmate.EventStore` separately.
- In tests, `:start_event_store` is false: tests start `Forkmate.CommandedApp`, `Forkmate.Games.Projections.GameProjection`, and (for bot tests) the task supervisor and handler explicitly with `start_supervised!`.
- Bot seat id format: `bot:stockfish:<level>` with level one of `easy`, `medium`, `hard`, `max`. The human seat stays `"Player 1"`.
- Level presets (Stockfish options + `go movetime`): easy = `UCI_LimitStrength=false`, `Skill Level=0`, 50 ms; medium = `UCI_LimitStrength=true`, `UCI_Elo=1400`, 300 ms; hard = `UCI_LimitStrength=true`, `UCI_Elo=2000`, 600 ms; max = `UCI_LimitStrength=false`, `Skill Level=20`, 1000 ms. Every search sets all of these options.
- Stockfish binary: `STOCKFISH_PATH` env var, else `stockfish` on `PATH`.
- Commit messages: no AI attribution lines of any kind (user's global instruction).
- Update Storybook stories only if a `GameComponents` function changes (this plan changes none).

## Review Focus

- Human tries to move or resign as the bot (via `?as=`, the flip event, or a forged event): must be impossible in a bot game. (Task 5)
- Bot is White and moves first: the board must have a move on load without any human action. (Task 3)
- Bot to move in a position with no legal moves (mate or stalemate): no Stockfish call, no error. (Task 3)
- Duplicate or replayed `MoveMade` delivery: bot must not play two replies from one node. (Task 3)
- Stockfish binary missing or crashing: game creation refuses with a flash; a mid-game failure is logged and the game stays playable. (Tasks 2, 4)
- Invalid or missing `level`/`color` form params: rejected, no game created. (Task 4)
- Human offers a draw to the bot: bot declines. (Task 3)
- Human rewinds and branches from an earlier own move: bot replies from the new branch. (Task 3)

---

## File Structure

| File | Responsibility |
|---|---|
| `lib/forkmate/bots/seat.ex` | Pure helpers for bot seat ids, levels, labels, human colour |
| `lib/forkmate/bots/bot.ex` | `Bot` behaviour |
| `lib/forkmate/bots.ex` | Facade: picks the configured `Bot` impl |
| `lib/forkmate/bots/stockfish/uci.ex` | Pure UCI helpers: level presets, command lists, bestmove parsing, binary lookup |
| `lib/forkmate/bots/stockfish/worker.ex` | GenServer owning one Stockfish Port |
| `lib/forkmate/bots/stockfish/pool.ex` | Supervisor of N workers, naming |
| `lib/forkmate/bots/stockfish.ex` | `Bot` impl over the pool |
| `lib/forkmate/bots/player.ex` | Commanded event handler that plays the bot's moves |
| `lib/forkmate/application.ex` | Start task supervisor, pool, handler |
| `lib/forkmate_web/controllers/page_controller.ex` | `mode=bot` game creation |
| `lib/forkmate_web/controllers/page_html/home.html.heex` | "Play vs computer" form |
| `lib/forkmate_web/live/game_live.ex` | Locked perspective, labels, thinking indicator |
| `test/support/fake_bot.ex`, `test/support/unavailable_bot.ex` | Test doubles |
| `mise.toml`, `README.md` | Stockfish provisioning and credit |

---

### Task 1: Seat, Bot behaviour, facade, fakes

**Files:**
- Create: `lib/forkmate/bots/seat.ex`, `lib/forkmate/bots/bot.ex`, `lib/forkmate/bots.ex`
- Create: `test/support/fake_bot.ex`, `test/support/unavailable_bot.ex`
- Modify: `config/config.exs` (add `:bot`), `config/test.exs` (use the fake)
- Test: `test/forkmate/bots/seat_test.exs`

**Interfaces:**
- Produces:
  - `Forkmate.Bots.Seat.levels() :: [:easy | :medium | :hard | :max]`
  - `Seat.new(level) :: String.t()`
  - `Seat.parse_level(String.t() | nil) :: {:ok, level} | {:error, :invalid_level}`
  - `Seat.bot?(String.t() | nil) :: boolean`
  - `Seat.level(String.t()) :: {:ok, level} | :error`
  - `Seat.label(String.t()) :: String.t()` (bot → `"Stockfish (Medium)"`, anything else unchanged)
  - `Seat.human_color(white_id, black_id) :: :white | :black | nil` (colour of the single human when exactly one seat is a bot)
  - `Forkmate.Bots.Bot` behaviour: `best_move(fen :: String.t(), level) :: {:ok, uci :: String.t()} | {:error, term}`, `available?() :: boolean`
  - `Forkmate.Bots.best_move/2`, `Forkmate.Bots.available?/0` (delegate to `Application.get_env(:forkmate, :bot)`)
  - `Forkmate.Bots.FakeBot` (first legal move in UCI), `Forkmate.Bots.UnavailableBot`

- [ ] **Step 1: Write the failing test**

```elixir
defmodule Forkmate.Bots.SeatTest do
  use ExUnit.Case, async: true

  alias Forkmate.Bots.Seat

  test "new/1 builds a bot seat id" do
    assert Seat.new(:medium) == "bot:stockfish:medium"
  end

  test "parse_level/1 accepts known levels and rejects the rest" do
    assert Seat.parse_level("easy") == {:ok, :easy}
    assert Seat.parse_level("max") == {:ok, :max}
    assert Seat.parse_level("impossible") == {:error, :invalid_level}
    assert Seat.parse_level(nil) == {:error, :invalid_level}
  end

  test "bot?/1 and level/1" do
    assert Seat.bot?("bot:stockfish:hard")
    refute Seat.bot?("Player 1")
    refute Seat.bot?(nil)
    assert Seat.level("bot:stockfish:hard") == {:ok, :hard}
    assert Seat.level("bot:stockfish:nope") == :error
    assert Seat.level("Player 1") == :error
  end

  test "label/1" do
    assert Seat.label("bot:stockfish:medium") == "Stockfish (Medium)"
    assert Seat.label("Player 1") == "Player 1"
  end

  test "human_color/2 is the colour of the lone human, nil otherwise" do
    bot = Seat.new(:easy)
    assert Seat.human_color("Player 1", bot) == :white
    assert Seat.human_color(bot, "Player 1") == :black
    assert Seat.human_color("Player 1", "Player 2") == nil
    assert Seat.human_color(bot, Seat.new(:hard)) == nil
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/forkmate/bots/seat_test.exs`
Expected: FAIL (`Forkmate.Bots.Seat` is undefined).

- [ ] **Step 3: Implement**

`lib/forkmate/bots/seat.ex`:

```elixir
defmodule Forkmate.Bots.Seat do
  @moduledoc """
  Helpers for bot seats. A bot is an ordinary player id of the form
  `bot:stockfish:<level>`, so the `Game` aggregate needs no special casing.
  """

  @prefix "bot:stockfish:"

  @type level :: :easy | :medium | :hard | :max

  @spec levels() :: [level()]
  def levels, do: [:easy, :medium, :hard, :max]

  @spec new(level()) :: String.t()
  def new(level) when level in [:easy, :medium, :hard, :max], do: @prefix <> Atom.to_string(level)

  @spec parse_level(String.t() | nil) :: {:ok, level()} | {:error, :invalid_level}
  def parse_level(value) do
    case to_level(value) do
      {:ok, level} -> {:ok, level}
      :error -> {:error, :invalid_level}
    end
  end

  @spec bot?(String.t() | nil) :: boolean()
  def bot?(@prefix <> _), do: true
  def bot?(_), do: false

  @spec level(String.t()) :: {:ok, level()} | :error
  def level(@prefix <> name), do: to_level(name)
  def level(_), do: :error

  @spec label(String.t()) :: String.t()
  def label(@prefix <> name = id) do
    case to_level(name) do
      {:ok, level} -> "Stockfish (#{level |> Atom.to_string() |> String.capitalize()})"
      :error -> id
    end
  end

  def label(id), do: id

  @spec human_color(String.t(), String.t()) :: :white | :black | nil
  def human_color(white_id, black_id) do
    case {bot?(white_id), bot?(black_id)} do
      {true, false} -> :black
      {false, true} -> :white
      _ -> nil
    end
  end

  defp to_level("easy"), do: {:ok, :easy}
  defp to_level("medium"), do: {:ok, :medium}
  defp to_level("hard"), do: {:ok, :hard}
  defp to_level("max"), do: {:ok, :max}
  defp to_level(_), do: :error
end
```

`lib/forkmate/bots/bot.ex`:

```elixir
defmodule Forkmate.Bots.Bot do
  @moduledoc """
  Behaviour for computer opponents. Implementations return a move in UCI
  notation for the position given as FEN.
  """

  alias Forkmate.Bots.Seat

  @callback best_move(fen :: String.t(), Seat.level()) :: {:ok, String.t()} | {:error, term()}
  @callback available?() :: boolean()
end
```

`lib/forkmate/bots.ex`:

```elixir
defmodule Forkmate.Bots do
  @moduledoc """
  Facade over the configured `Forkmate.Bots.Bot` implementation
  (`config :forkmate, :bot, Module`).
  """

  @spec impl() :: module()
  def impl, do: Application.get_env(:forkmate, :bot, Forkmate.Bots.Stockfish)

  @spec best_move(String.t(), Forkmate.Bots.Seat.level()) :: {:ok, String.t()} | {:error, term()}
  def best_move(fen, level), do: impl().best_move(fen, level)

  @spec available?() :: boolean()
  def available?, do: impl().available?()
end
```

`test/support/fake_bot.ex`:

```elixir
defmodule Forkmate.Bots.FakeBot do
  @moduledoc false
  @behaviour Forkmate.Bots.Bot

  alias Forkmate.Chess.{Engine, Move, Position}

  @impl true
  def available?, do: true

  @impl true
  def best_move(fen, _level) do
    with {:ok, pos} <- Position.from_fen(fen),
         [move | _] <- Engine.legal_moves(pos) do
      {:ok, Move.to_uci(move)}
    else
      _ -> {:error, :no_move}
    end
  end
end
```

`test/support/unavailable_bot.ex`:

```elixir
defmodule Forkmate.Bots.UnavailableBot do
  @moduledoc false
  @behaviour Forkmate.Bots.Bot

  @impl true
  def available?, do: false

  @impl true
  def best_move(_fen, _level), do: {:error, :unavailable}
end
```

Config: in `config/config.exs` after the `:chess_engine` line add `config :forkmate, :bot, Forkmate.Bots.Stockfish`. In `config/test.exs` add `config :forkmate, :bot, Forkmate.Bots.FakeBot`.

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/forkmate/bots/seat_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/forkmate/bots.ex lib/forkmate/bots test/support/fake_bot.ex test/support/unavailable_bot.ex test/forkmate/bots config/config.exs config/test.exs
git commit -m "feat(bots): add bot seats, Bot behaviour and test doubles"
```

---

### Task 2: Stockfish UCI helpers, worker and pool

**Files:**
- Create: `lib/forkmate/bots/stockfish/uci.ex`, `worker.ex`, `pool.ex`, `lib/forkmate/bots/stockfish.ex`
- Modify: `test/test_helper.exs` (exclude `:stockfish` when no binary)
- Test: `test/forkmate/bots/stockfish/uci_test.exs`, `test/forkmate/bots/stockfish_test.exs`

**Interfaces:**
- Consumes: `Seat.level()` type, `Bot` behaviour (Task 1).
- Produces:
  - `UCI.search_commands(fen, level) :: [String.t()]`
  - `UCI.parse_bestmove(line) :: {:ok, uci} | {:error, :no_move} | :ignore`
  - `UCI.executable() :: String.t() | nil`
  - `Forkmate.Bots.Stockfish` (implements `Bot`), `Forkmate.Bots.Stockfish.Pool` (supervisor; `start_link/1`, `size/0`, `worker_name/1`), `Forkmate.Bots.Stockfish.Worker`.

- [ ] **Step 1: Write the failing UCI tests**

```elixir
defmodule Forkmate.Bots.Stockfish.UCITest do
  use ExUnit.Case, async: true

  alias Forkmate.Bots.Stockfish.UCI

  @fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  test "search_commands/2 sets every option, then position and go" do
    assert UCI.search_commands(@fen, :medium) == [
             "setoption name Skill Level value 20",
             "setoption name UCI_LimitStrength value true",
             "setoption name UCI_Elo value 1400",
             "position fen " <> @fen,
             "go movetime 300"
           ]
  end

  test "easy and max do not limit strength by Elo" do
    easy = UCI.search_commands(@fen, :easy)
    assert "setoption name Skill Level value 0" in easy
    assert "setoption name UCI_LimitStrength value false" in easy
    assert List.last(easy) == "go movetime 50"

    max = UCI.search_commands(@fen, :max)
    assert "setoption name Skill Level value 20" in max
    assert "setoption name UCI_LimitStrength value false" in max
    assert List.last(max) == "go movetime 1000"
  end

  test "hard uses Elo 2000" do
    assert "setoption name UCI_Elo value 2000" in UCI.search_commands(@fen, :hard)
  end

  test "parse_bestmove/1" do
    assert UCI.parse_bestmove("bestmove e2e4 ponder e7e5") == {:ok, "e2e4"}
    assert UCI.parse_bestmove("bestmove e7e8q") == {:ok, "e7e8q"}
    assert UCI.parse_bestmove("bestmove (none)") == {:error, :no_move}
    assert UCI.parse_bestmove("info depth 3 score cp 20") == :ignore
    assert UCI.parse_bestmove("readyok") == :ignore
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/forkmate/bots/stockfish/uci_test.exs`
Expected: FAIL (module undefined).

- [ ] **Step 3: Implement the UCI helpers**

`lib/forkmate/bots/stockfish/uci.ex`:

```elixir
defmodule Forkmate.Bots.Stockfish.UCI do
  @moduledoc """
  Pure helpers for talking UCI to Stockfish: level presets, command lists and
  `bestmove` parsing.
  """

  alias Forkmate.Bots.Seat

  # {Skill Level, limit strength?, Elo, movetime in ms}
  @presets %{
    easy: {0, false, nil, 50},
    medium: {20, true, 1400, 300},
    hard: {20, true, 2000, 600},
    max: {20, false, nil, 1000}
  }

  @spec search_commands(String.t(), Seat.level()) :: [String.t()]
  def search_commands(fen, level) do
    {skill, limit?, elo, movetime} = Map.fetch!(@presets, level)

    [
      "setoption name Skill Level value #{skill}",
      "setoption name UCI_LimitStrength value #{limit?}"
    ] ++
      if(elo, do: ["setoption name UCI_Elo value #{elo}"], else: []) ++
      ["position fen " <> fen, "go movetime #{movetime}"]
  end

  @spec parse_bestmove(String.t()) :: {:ok, String.t()} | {:error, :no_move} | :ignore
  def parse_bestmove("bestmove (none)" <> _), do: {:error, :no_move}

  def parse_bestmove("bestmove " <> rest) do
    case String.split(rest, " ", parts: 2) do
      [move | _] when move != "" -> {:ok, move}
      _ -> {:error, :no_move}
    end
  end

  def parse_bestmove(_line), do: :ignore

  @doc """
  Path of the Stockfish binary: `STOCKFISH_PATH`, else `stockfish` on `PATH`.
  Returns `nil` when neither resolves to an existing file.
  """
  @spec executable() :: String.t() | nil
  def executable do
    path = System.get_env("STOCKFISH_PATH") || System.find_executable("stockfish")
    if path && File.regular?(path), do: path
  end
end
```

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/forkmate/bots/stockfish/uci_test.exs`
Expected: PASS.

- [ ] **Step 5: Write the worker, pool and Stockfish module**

`lib/forkmate/bots/stockfish/worker.ex`:

```elixir
defmodule Forkmate.Bots.Stockfish.Worker do
  @moduledoc """
  Owns one long-lived Stockfish process through a Port. The process is started
  lazily on the first request, so a missing binary never prevents boot. Any
  error closes the port, so stale output can never answer a later request.
  """

  use GenServer

  alias Forkmate.Bots.Stockfish.UCI

  @handshake_timeout 5_000
  @search_timeout 10_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, nil, name: Keyword.fetch!(opts, :name))

  @spec best_move(GenServer.name(), String.t(), Forkmate.Bots.Seat.level()) ::
          {:ok, String.t()} | {:error, term()}
  def best_move(name, fen, level) do
    GenServer.call(name, {:best_move, fen, level}, @search_timeout + @handshake_timeout)
  end

  @impl true
  def init(nil), do: {:ok, %{port: nil}}

  @impl true
  def handle_call({:best_move, fen, level}, _from, state) do
    with {:ok, port} <- ensure_port(state.port),
         :ok <- send_commands(port, UCI.search_commands(fen, level)),
         {:ok, move} <- await_bestmove(port) do
      {:reply, {:ok, move}, %{state | port: port}}
    else
      {:error, reason} ->
        close(state.port)
        {:reply, {:error, reason}, %{state | port: nil}}
    end
  end

  @impl true
  def handle_info({port, {:exit_status, _status}}, %{port: port} = state) do
    {:noreply, %{state | port: nil}}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp ensure_port(port) when is_port(port), do: {:ok, port}

  defp ensure_port(nil) do
    case UCI.executable() do
      nil ->
        {:error, :stockfish_not_found}

      path ->
        port =
          Port.open({:spawn_executable, path}, [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            {:line, 4096}
          ])

        with :ok <- send_commands(port, ["uci"]),
             {:ok, _} <- await_line(port, &(&1 == "uciok"), @handshake_timeout) do
          {:ok, port}
        else
          {:error, reason} ->
            close(port)
            {:error, reason}
        end
    end
  end

  defp send_commands(port, commands) do
    Port.command(port, Enum.map(commands, &[&1, ?\n]))
    :ok
  rescue
    ArgumentError -> {:error, :port_closed}
  end

  defp await_bestmove(port) do
    result =
      await_line(
        port,
        fn line -> UCI.parse_bestmove(line) != :ignore end,
        @search_timeout
      )

    case result do
      {:ok, line} -> UCI.parse_bestmove(line)
      {:error, reason} -> {:error, reason}
    end
  end

  defp await_line(port, match?, timeout) do
    receive do
      {^port, {:data, {:eol, line}}} ->
        if match?.(line), do: {:ok, line}, else: await_line(port, match?, timeout)

      {^port, {:data, {:noeol, _partial}}} ->
        await_line(port, match?, timeout)

      {^port, {:exit_status, status}} ->
        {:error, {:exited, status}}
    after
      timeout -> {:error, :timeout}
    end
  end

  defp close(port) when is_port(port) do
    Port.close(port)
  rescue
    ArgumentError -> :ok
  end

  defp close(_), do: :ok
end
```

`lib/forkmate/bots/stockfish/pool.ex`:

```elixir
defmodule Forkmate.Bots.Stockfish.Pool do
  @moduledoc """
  Supervises a fixed number of `Forkmate.Bots.Stockfish.Worker` processes.
  Pool size comes from `config :forkmate, Forkmate.Bots.Stockfish, pool_size: n`
  (default 2).
  """

  use Supervisor

  alias Forkmate.Bots.Stockfish.Worker

  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @spec size() :: pos_integer()
  def size do
    :forkmate
    |> Application.get_env(Forkmate.Bots.Stockfish, [])
    |> Keyword.get(:pool_size, 2)
  end

  @spec worker_name(non_neg_integer()) :: atom()
  def worker_name(index), do: :"forkmate_stockfish_worker_#{index}"

  @impl true
  def init(_opts) do
    children =
      for index <- 0..(size() - 1) do
        Supervisor.child_spec({Worker, name: worker_name(index)}, id: {Worker, index})
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

`lib/forkmate/bots/stockfish.ex`:

```elixir
defmodule Forkmate.Bots.Stockfish do
  @moduledoc """
  `Forkmate.Bots.Bot` implementation backed by a pool of Stockfish UCI
  processes (see `Forkmate.Bots.Stockfish.Pool`).
  """

  @behaviour Forkmate.Bots.Bot

  alias Forkmate.Bots.Stockfish.{Pool, UCI, Worker}

  @impl true
  def available?, do: UCI.executable() != nil

  @impl true
  def best_move(fen, level) do
    index = rem(System.unique_integer([:positive]), Pool.size())
    Worker.best_move(Pool.worker_name(index), fen, level)
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end
end
```

`test/test_helper.exs`:

```elixir
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Forkmate.Repo, :manual)

unless Forkmate.Bots.Stockfish.available?() do
  ExUnit.configure(exclude: [:stockfish])
end
```

- [ ] **Step 6: Write the integration test (tagged)**

`test/forkmate/bots/stockfish_test.exs`:

```elixir
defmodule Forkmate.Bots.StockfishTest do
  use ExUnit.Case, async: false

  alias Forkmate.Bots.Seat
  alias Forkmate.Bots.Stockfish
  alias Forkmate.Chess.{Engine, Move, Position}

  @moduletag :stockfish

  setup do
    start_supervised!(Stockfish.Pool)
    :ok
  end

  for level <- [:easy, :medium, :hard, :max] do
    test "returns a legal move at level #{level}" do
      pos = Position.from_fen!(Position.start_fen())
      assert {:ok, uci} = Stockfish.best_move(Position.start_fen(), unquote(level))
      assert {:ok, move} = Move.from_uci(uci)
      assert move in Engine.legal_moves(pos)
    end
  end

  test "finds mate in one at max level" do
    # White to play Qh5#? No: use a simple back-rank mate: Ra8#
    fen = "6k1/5ppp/8/8/8/8/8/R3K3 w - - 0 1"
    assert {:ok, "a1a8"} = Stockfish.best_move(fen, :max)
  end

  test "levels list matches the presets" do
    for level <- Seat.levels() do
      assert {:ok, _} = Stockfish.best_move(Position.start_fen(), level)
    end
  end
end
```

(`Position.from_fen!/1` and `Position.start_fen/0` exist; `Move` equality compares `from`/`to`/`promotion`, which `Move.from_uci/1` and `Engine.legal_moves/1` share.)

- [ ] **Step 7: Verify provisioning and run the integration tests**

Provisioning has to exist first: do Task 6 steps 1-3 now if `stockfish` is not yet on your `PATH` (`which stockfish`), then:

Run: `mix test test/forkmate/bots/stockfish_test.exs`
Expected: PASS with Stockfish installed; with it absent the file's tests are excluded and the run shows "0 tests" (not a failure).

Run: `mix test test/forkmate/bots/stockfish/uci_test.exs test/forkmate/bots/seat_test.exs`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/forkmate/bots test/forkmate/bots test/test_helper.exs
git commit -m "feat(bots): add Stockfish UCI worker pool"
```

---

### Task 3: `Bots.Player` event handler and application wiring

**Files:**
- Create: `lib/forkmate/bots/player.ex`
- Modify: `lib/forkmate/application.ex` (`event_store_children/0`)
- Test: `test/forkmate/bots/player_test.exs`

**Interfaces:**
- Consumes: `Seat.bot?/1`, `Seat.level/1` (Task 1); `Bots.best_move/2` (Task 1); `Games.get_game/1`, `Games.make_move/1`, `Games.decline_draw/2`; `Engine.legal_moves/1`; `Move.from_uci/1`; `Square.to_name/1`; events `GameStarted{game_id, root_node_id, white_player_id, black_player_id, initial_fen}`, `MoveMade{game_id, node_id, fen}`, `DrawOffered{game_id, player_id}`.
- Produces: `Forkmate.Bots.Player` (child spec startable with `start_supervised!(Forkmate.Bots.Player)`), and the named task supervisor `Forkmate.Bots.TaskSupervisor` (must be running for the handler to schedule work).

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule Forkmate.Bots.PlayerTest do
  use Forkmate.DataCase

  alias Ecto.Adapters.SQL.Sandbox
  alias Forkmate.Bots.{Player, Seat}
  alias Forkmate.CommandedApp
  alias Forkmate.Games
  alias Forkmate.Games.Projections.GameProjection

  @human "Player 1"

  setup do
    Sandbox.mode(Forkmate.Repo, {:shared, self()})
    start_supervised!(CommandedApp)
    start_supervised!(GameProjection)
    start_supervised!({Task.Supervisor, name: Forkmate.Bots.TaskSupervisor})
    start_supervised!(Player)
    :ok
  end

  defp new_game(white, black, attrs \\ %{}) do
    game_id = "bot-game-" <> Ecto.UUID.generate()

    {:ok, ^game_id} =
      Games.start_game(Map.merge(%{game_id: game_id, white_player_id: white, black_player_id: black}, attrs))

    game_id
  end

  defp eventually(fun, tries \\ 100) do
    case fun.() do
      result when result not in [nil, false] ->
        result

      _ when tries > 0 ->
        Process.sleep(50)
        eventually(fun, tries - 1)

      other ->
        flunk("condition not met, last value: #{inspect(other)}")
    end
  end

  defp node_count(game_id), do: length(Games.list_nodes(game_id))

  test "bot plays White's first move on game start" do
    game_id = new_game(Seat.new(:easy), @human)
    eventually(fn -> node_count(game_id) == 2 end)
  end

  test "bot replies after the human moves" do
    bot = Seat.new(:easy)
    game_id = new_game(@human, bot)
    [root] = Games.list_nodes(game_id)

    assert :ok =
             Games.make_move(%{
               game_id: game_id,
               from_node_id: root.id,
               from: "e2",
               to: "e4",
               player_id: @human
             })

    eventually(fn -> node_count(game_id) == 3 end)
    # And it stops there: it is the human's turn again.
    Process.sleep(300)
    assert node_count(game_id) == 3
  end

  test "bot replies from a new branch when the human rewinds and plays differently" do
    bot = Seat.new(:easy)
    game_id = new_game(@human, bot)
    [root] = Games.list_nodes(game_id)

    :ok = Games.make_move(%{game_id: game_id, from_node_id: root.id, from: "e2", to: "e4", player_id: @human})
    eventually(fn -> node_count(game_id) == 3 end)

    :ok = Games.make_move(%{game_id: game_id, from_node_id: root.id, from: "d2", to: "d4", player_id: @human})
    eventually(fn -> node_count(game_id) == 5 end)
  end

  test "bot does not reply when there are no legal moves" do
    # Black to move is already checkmated (fool's mate position), White is the human.
    fen = "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3"
    game_id = new_game(Seat.new(:easy), @human, %{initial_fen: fen})
    Process.sleep(300)
    assert node_count(game_id) == 1
  end

  test "bot declines a draw offered by the human" do
    bot = Seat.new(:easy)
    game_id = new_game(@human, bot)
    assert :ok = Games.offer_draw(game_id, @human)

    eventually(fn -> Games.get_game(game_id).draw_offered_by == nil end)
  end

  test "human-vs-human games are left alone" do
    game_id = new_game(@human, "Player 2")
    [root] = Games.list_nodes(game_id)
    :ok = Games.make_move(%{game_id: game_id, from_node_id: root.id, from: "e2", to: "e4", player_id: @human})
    Process.sleep(300)
    assert node_count(game_id) == 2
  end
end
```

(In the "no legal moves" test the FEN is White-to-move-and-mated: White has no legal moves and the bot is White. If `Engine.validate/1` rejects it, replace with any stalemate FEN where the bot has the move, e.g. `7k/5Q2/6K1/8/8/8/8/8 b - - 0 1` with the bot as Black.)

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/forkmate/bots/player_test.exs`
Expected: FAIL (`Forkmate.Bots.Player` undefined).

- [ ] **Step 3: Implement the handler**

`lib/forkmate/bots/player.ex`:

```elixir
defmodule Forkmate.Bots.Player do
  @moduledoc """
  Commanded event handler that plays for bot seats.

  It reacts to `GameStarted` and `MoveMade`: when the side to move is a bot, it
  asks the configured `Forkmate.Bots.Bot` for a move in a supervised task (so a
  slow search never blocks event handling) and dispatches an ordinary
  `MakeMove`. The reply's node id is derived from the node it answers, so a
  duplicate delivery fails with `:node_id_taken` instead of double-moving.
  It also declines draw offers made to a bot.
  """

  use Commanded.Event.Handler,
    application: Forkmate.CommandedApp,
    name: "Forkmate.Bots.Player",
    start_from: :current

  require Logger

  alias Forkmate.Bots
  alias Forkmate.Bots.Seat
  alias Forkmate.Chess.{Engine, Move, Position, Square}
  alias Forkmate.Games
  alias Forkmate.Games.Events.{DrawOffered, GameStarted, MoveMade}

  @task_supervisor Forkmate.Bots.TaskSupervisor

  def handle(%GameStarted{} = event, _metadata) do
    schedule_reply(
      event.game_id,
      event.root_node_id,
      event.initial_fen,
      event.white_player_id,
      event.black_player_id
    )
  end

  def handle(%MoveMade{} = event, _metadata) do
    case Games.get_game(event.game_id) do
      nil ->
        :ok

      game ->
        schedule_reply(
          event.game_id,
          event.node_id,
          event.fen,
          game.white_player_id,
          game.black_player_id
        )
    end
  end

  def handle(%DrawOffered{} = event, _metadata) do
    with %{} = game <- Games.get_game(event.game_id),
         bot_id when is_binary(bot_id) <- opposing_bot(game, event.player_id) do
      Games.decline_draw(event.game_id, bot_id)
    end

    :ok
  end

  defp opposing_bot(game, offerer) do
    other = if offerer == game.white_player_id, do: game.black_player_id, else: game.white_player_id
    if Seat.bot?(other) and not Seat.bot?(offerer), do: other
  end

  defp schedule_reply(game_id, node_id, fen, white_id, black_id) do
    with {:ok, pos} <- Position.from_fen(fen),
         bot_id when is_binary(bot_id) <- bot_to_move(pos.active_color, white_id, black_id),
         {:ok, level} <- Seat.level(bot_id),
         [_ | _] <- Engine.legal_moves(pos) do
      Task.Supervisor.start_child(@task_supervisor, fn ->
        play(game_id, node_id, fen, bot_id, level)
      end)
    end

    :ok
  end

  defp bot_to_move(color, white_id, black_id) do
    id = if color == :white, do: white_id, else: black_id
    if Seat.bot?(id), do: id
  end

  defp play(game_id, node_id, fen, bot_id, level) do
    with {:ok, uci} <- best_move_with_retry(fen, level),
         {:ok, %Move{} = move} <- Move.from_uci(uci),
         :ok <-
           Games.make_move(%{
             game_id: game_id,
             from_node_id: node_id,
             node_id: reply_node_id(node_id),
             from: Square.to_name(move.from),
             to: Square.to_name(move.to),
             promotion: move.promotion,
             player_id: bot_id
           }) do
      :ok
    else
      {:error, :node_id_taken} ->
        :ok

      other ->
        Logger.warning("Bot move failed for game #{game_id} at node #{node_id}: #{inspect(other)}")
        :error
    end
  end

  defp best_move_with_retry(fen, level) do
    case Bots.best_move(fen, level) do
      {:ok, _} = ok -> ok
      {:error, _} -> Bots.best_move(fen, level)
    end
  end

  defp reply_node_id(node_id) do
    <<uuid::binary-size(16), _rest::binary>> = :crypto.hash(:sha256, "bot-reply:" <> node_id)
    {:ok, id} = Ecto.UUID.load(uuid)
    id
  end
end
```

`lib/forkmate/application.ex`, replace `event_store_children/0` list:

```elixir
      [
        Forkmate.CommandedApp,
        Forkmate.Games.Projections.GameProjection,
        {Task.Supervisor, name: Forkmate.Bots.TaskSupervisor},
        Forkmate.Bots.Stockfish.Pool,
        Forkmate.Bots.Player
      ]
```

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/forkmate/bots/player_test.exs`
Expected: PASS. If a test fails because the bot's move targets differ from what you asserted, remember the fake picks the first legal move; the tests only count nodes.

Run: `mix test`
Expected: PASS (existing suite unaffected).

- [ ] **Step 5: Commit**

```bash
git add lib/forkmate/bots/player.ex lib/forkmate/application.ex test/forkmate/bots/player_test.exs
git commit -m "feat(bots): play bot moves from a Commanded event handler"
```

---

### Task 4: Start a bot game from the home page

**Files:**
- Modify: `lib/forkmate_web/controllers/page_controller.ex`, `lib/forkmate_web/controllers/page_html/home.html.heex`
- Test: `test/forkmate_web/controllers/page_controller_test.exs`

**Interfaces:**
- Consumes: `Seat.parse_level/1`, `Seat.new/1`, `Seat.levels/0`, `Bots.available?/0`, `Games.start_game/1`.
- Produces: `POST /games` with `mode=bot&level=<easy|medium|hard|max>&color=<white|black|random>`. Human is `"Player 1"`.

- [ ] **Step 1: Write the failing tests** (append to the existing test module)

```elixir
  describe "POST /games with mode=bot" do
    alias Forkmate.Bots.Seat
    alias Forkmate.Games

    test "human as white", %{conn: conn} do
      conn = post(conn, ~p"/games", %{"mode" => "bot", "level" => "medium", "color" => "white"})
      assert %{id: game_id} = redirected_params(conn)
      game = Games.get_game(game_id)
      assert game.white_player_id == "Player 1"
      assert game.black_player_id == Seat.new(:medium)
    end

    test "human as black", %{conn: conn} do
      conn = post(conn, ~p"/games", %{"mode" => "bot", "level" => "hard", "color" => "black"})
      assert %{id: game_id} = redirected_params(conn)
      game = Games.get_game(game_id)
      assert game.white_player_id == Seat.new(:hard)
      assert game.black_player_id == "Player 1"
    end

    test "random colour gives the human exactly one seat", %{conn: conn} do
      conn = post(conn, ~p"/games", %{"mode" => "bot", "level" => "easy", "color" => "random"})
      assert %{id: game_id} = redirected_params(conn)
      game = Games.get_game(game_id)
      assert Seat.human_color(game.white_player_id, game.black_player_id) in [:white, :black]
    end

    test "rejects an unknown level", %{conn: conn} do
      conn = post(conn, ~p"/games", %{"mode" => "bot", "level" => "godlike", "color" => "white"})
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid"
    end

    test "rejects an unknown colour", %{conn: conn} do
      conn = post(conn, ~p"/games", %{"mode" => "bot", "level" => "easy", "color" => "green"})
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid"
    end

    test "rejects missing options", %{conn: conn} do
      conn = post(conn, ~p"/games", %{"mode" => "bot"})
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid"
    end

    test "refuses when the bot is unavailable", %{conn: conn} do
      previous = Application.get_env(:forkmate, :bot)
      Application.put_env(:forkmate, :bot, Forkmate.Bots.UnavailableBot)
      on_exit(fn -> Application.put_env(:forkmate, :bot, previous) end)

      conn = post(conn, ~p"/games", %{"mode" => "bot", "level" => "easy", "color" => "white"})
      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "unavailable"
    end
  end

  test "home page offers the computer game form", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ "Play vs computer"
    assert html =~ ~s(name="level")
    assert html =~ ~s(name="color")
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/forkmate_web/controllers/page_controller_test.exs`
Expected: FAIL (bot params fall through to the plain-game clause; no form).

- [ ] **Step 3: Implement**

`lib/forkmate_web/controllers/page_controller.ex`:

```elixir
defmodule ForkmateWeb.PageController do
  use ForkmateWeb, :controller

  alias Forkmate.Bots
  alias Forkmate.Bots.Seat
  alias Forkmate.Games

  @human "Player 1"

  def home(conn, _params) do
    render(conn, :home, levels: Seat.levels())
  end

  def create_game(conn, %{"mode" => "bot"} = params) do
    with {:ok, level} <- Seat.parse_level(params["level"]),
         {:ok, color} <- resolve_color(params["color"]),
         :ok <- ensure_bot_available(),
         {:ok, game_id} <- Games.start_game(seats(color, Seat.new(level))) do
      redirect(conn, to: ~p"/games/#{game_id}")
    else
      {:error, reason} ->
        conn
        |> put_flash(:error, error_message(reason))
        |> redirect(to: ~p"/")
    end
  end

  def create_game(conn, _params) do
    game_id = Ecto.UUID.generate()

    case Games.start_game(%{
           game_id: game_id,
           white_player_id: "Player 1",
           black_player_id: "Player 2"
         }) do
      {:ok, _} ->
        redirect(conn, to: ~p"/games/#{game_id}")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Failed to create game: #{inspect(reason)}")
        |> redirect(to: ~p"/")
    end
  end

  defp resolve_color("white"), do: {:ok, :white}
  defp resolve_color("black"), do: {:ok, :black}
  defp resolve_color("random"), do: {:ok, Enum.random([:white, :black])}
  defp resolve_color(_), do: {:error, :invalid_color}

  defp ensure_bot_available do
    if Bots.available?(), do: :ok, else: {:error, :bot_unavailable}
  end

  defp seats(:white, bot_id), do: %{white_player_id: @human, black_player_id: bot_id}
  defp seats(:black, bot_id), do: %{white_player_id: bot_id, black_player_id: @human}

  defp error_message(:bot_unavailable), do: "Computer opponent unavailable."
  defp error_message(reason) when reason in [:invalid_level, :invalid_color], do: "Invalid computer game options."
  defp error_message(reason), do: "Failed to create game: #{inspect(reason)}"
end
```

`lib/forkmate_web/controllers/page_html/home.html.heex`: inside the `<div class="mt-2 flex gap-3">` block, keep the existing New Game form and Storybook link, and add this block directly after that div (before `<div class="flex">`):

```heex
    <.form
      for={%{}}
      action={~p"/games"}
      method="post"
      class="mt-4 flex flex-wrap items-end gap-3 rounded-box border border-base-300 bg-base-200/50 p-4"
    >
      <input type="hidden" name="mode" value="bot" />
      <h3 class="w-full text-sm font-semibold uppercase tracking-wider text-base-content/70">
        Play vs computer
      </h3>
      <label class="flex flex-col gap-1 text-sm">
        Difficulty
        <select name="level" class="select select-bordered select-sm">
          <option :for={level <- @levels} value={level} selected={level == :medium}>
            {level |> Atom.to_string() |> String.capitalize()}
          </option>
        </select>
      </label>
      <label class="flex flex-col gap-1 text-sm">
        Play as
        <select name="color" class="select select-bordered select-sm">
          <option value="white">White</option>
          <option value="black">Black</option>
          <option value="random">Random</option>
        </select>
      </label>
      <button type="submit" class="btn btn-secondary btn-sm">Start</button>
    </.form>
```

`PageHTML` (`lib/forkmate_web/controllers/page_html.ex`) embeds templates with `embed_templates`; the new `levels` assign needs no change there.

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/forkmate_web/controllers/page_controller_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/forkmate_web/controllers test/forkmate_web/controllers
git commit -m "feat(web): start a game against the computer from the home page"
```

---

### Task 5: Bot-aware `GameLive`

**Files:**
- Modify: `lib/forkmate_web/live/game_live.ex`
- Test: `test/forkmate_web/live/game_live_test.exs`

**Interfaces:**
- Consumes: `Seat.human_color/2`, `Seat.label/1`, `Seat.bot?/1`.
- Produces: assigns `bot_game` (boolean) and `bot_thinking` (boolean); element `#bot-thinking` shown while the bot is to move on the latest node of an ongoing game.

- [ ] **Step 1: Write the failing tests** (append inside the existing test module; the module's `setup` already starts Commanded and the projection)

```elixir
  describe "bot games" do
    alias Forkmate.Bots.Seat

    defp bot_game(white, black) do
      game_id = "live-bot-" <> Ecto.UUID.generate()
      {:ok, ^game_id} = Games.start_game(%{game_id: game_id, white_player_id: white, black_player_id: black})
      game_id
    end

    test "shows the bot label and hides the flip button", %{conn: conn} do
      game_id = bot_game("Player 1", Seat.new(:medium))
      {:ok, view, html} = live(conn, ~p"/games/#{game_id}")

      assert html =~ "Stockfish (Medium)"
      refute has_element?(view, "button[phx-click='switch_perspective']")
    end

    test "perspective is locked to the human colour, ignoring ?as=", %{conn: conn} do
      game_id = bot_game("Player 1", Seat.new(:easy))
      {:ok, _view, html} = live(conn, ~p"/games/#{game_id}?as=black")
      refute html =~ "Playing as: <strong>Black"
      assert html =~ "orientation" or html =~ "main-chess-board"

      game_id = bot_game(Seat.new(:easy), "Player 1")
      {:ok, view, _html} = live(conn, ~p"/games/#{game_id}?as=white")
      assert render(view) =~ "Stockfish (Easy)"
    end

    test "switch_perspective is a no-op in a bot game", %{conn: conn} do
      game_id = bot_game(Seat.new(:easy), "Player 1")
      {:ok, view, _html} = live(conn, ~p"/games/#{game_id}")
      before = render(view)
      render_hook(view, "switch_perspective", %{})
      assert render(view) == before
    end

    test "human cannot move the bot's pieces", %{conn: conn} do
      # Human is black; White (the bot) is to move, so no piece is selectable.
      game_id = bot_game(Seat.new(:easy), "Player 1")
      {:ok, view, _html} = live(conn, ~p"/games/#{game_id}")

      view |> element("rect[phx-value-square='e2']") |> render_click()
      refute has_element?(view, "[data-selected='true']")
      assert length(Games.list_nodes(game_id)) == 1
    end

    test "shows the thinking indicator while the bot is to move", %{conn: conn} do
      game_id = bot_game(Seat.new(:easy), "Player 1")
      {:ok, view, _html} = live(conn, ~p"/games/#{game_id}")
      assert has_element?(view, "#bot-thinking")
    end

    test "no thinking indicator on the human's turn or in human games", %{conn: conn} do
      game_id = bot_game("Player 1", Seat.new(:easy))
      {:ok, view, _html} = live(conn, ~p"/games/#{game_id}")
      refute has_element?(view, "#bot-thinking")

      {:ok, view, _html} = live(conn, ~p"/games/#{bot_game("Player 1", "Player 2")}")
      refute has_element?(view, "#bot-thinking")
    end
  end
```

(Before relying on the selector in "human cannot move the bot's pieces", open `GameComponents.board` and use whatever attribute marks a selected square; if there is none, assert instead that clicking `e2` followed by `e4` leaves `Games.list_nodes/1` at one node. Likewise tighten the second test's `Playing as` assertion to the exact rendered text once you see the heading markup.)

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/forkmate_web/live/game_live_test.exs`
Expected: FAIL (label not shown, flip button present, no `#bot-thinking`).

- [ ] **Step 3: Implement** in `lib/forkmate_web/live/game_live.ex`

1. Add `alias Forkmate.Bots.Seat` (keep aliases alphabetical: after `Forkmate.Chess` and before `Forkmate.Games`... follow the existing order: `Forkmate.Bots.Seat`, `Forkmate.Chess.{Position, Square}`, `Forkmate.Games`, ...).

2. In `mount/3`, replace `perspective = parse_perspective(params["as"])` with `perspective = resolve_perspective(game, params)`. In `handle_params/3`, the game is fetched after the perspective today; reorder so `game` is loaded first:

```elixir
    case Games.get_game(game_id) do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/")}

      game ->
        node_id = params["node"] || game.current_node_id

        socket =
          socket
          |> assign(perspective: resolve_perspective(game, params))
          |> load_game_state(game, node_id)

        {:noreply, socket}
    end
```

3. Add the helper next to `parse_perspective/1`:

```elixir
  defp resolve_perspective(game, params) do
    Seat.human_color(game.white_player_id, game.black_player_id) ||
      parse_perspective(params["as"])
  end
```

4. Make the flip event a no-op in bot games:

```elixir
  def handle_event("switch_perspective", _params, socket) do
    if socket.assigns.bot_game do
      {:noreply, socket}
    else
      new_perspective = if socket.assigns.perspective == :white, do: :black, else: :white
      {:noreply, assign(socket, perspective: new_perspective)}
    end
  end
```

5. In `load_game_state/3`, compute and assign (add to the `assign(socket, ...)` list; `active_turn` is already computed above it):

```elixir
    bot_game = Seat.human_color(game.white_player_id, game.black_player_id) != nil

    bot_thinking =
      bot_game and game.status != "ended" and current_node_id == game.current_node_id and
        active_turn != socket.assigns.perspective
```

and add `bot_game: bot_game, bot_thinking: bot_thinking` to the assigns. (`socket.assigns.perspective` is set before `load_game_state` is called in both `mount` and `handle_params`.)

6. Template: add `:if={!@bot_game}` to the `switch_perspective` button; change the two `GameComponents.player_card` `name=` values to `{Seat.label(top_player)}` and `{Seat.label(bottom_player)}`; add directly under the bottom `player_card`:

```heex
              <p :if={@bot_thinking} id="bot-thinking" class="text-sm text-base-content/60">
                Computer is thinking…
              </p>
```

The draw-offer banner text uses raw ids: pass `from={Seat.label(...)}` as well where `GameComponents.draw_offer` receives `from` (the offer banner only shows when the *opponent* offered, which a bot never does, so this is optional; skip it).

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/forkmate_web/live/game_live_test.exs`
Expected: PASS, including all pre-existing tests (they use human-vs-human games, where `bot_game` is false and behaviour is unchanged).

- [ ] **Step 5: Commit**

```bash
git add lib/forkmate_web/live/game_live.ex test/forkmate_web/live/game_live_test.exs
git commit -m "feat(web): lock the board to the human in bot games and label the bot"
```

---

### Task 6: Provisioning, docs and final checks

**Files:**
- Modify: `mise.toml`, `README.md`, `CLAUDE.md` (architecture note)

**Interfaces:** none.

- [ ] **Step 1: Find the Stockfish release tag**

Run: `mise ls-remote github:official-stockfish/Stockfish | tail -5`
Expected: a list of release tags. Pick the newest `sf_<version>` tag (call it `<TAG>`).

- [ ] **Step 2: Add Stockfish to mise and install**

Edit `mise.toml` so `[tools]` gains (use the real tag):

```toml
"github:official-stockfish/Stockfish" = "<TAG>"
```

Run: `mise install && mise which stockfish`
Expected: a path. If mise reports "no matching asset", set a per-platform `asset_pattern` for the portable baseline build (for Intel/AMD Linux a name containing `x86-64` and not `avx`/`bmi`/`vnni`; for Apple Silicon `apple-silicon`) and rerun. Do not hardcode `avx2`.
If the `github:` backend cannot be made to work, stop and tell the user; the agreed fallback is a pinned download script with a SHA-256 check into `priv/stockfish/`.

- [ ] **Step 3: Smoke test the binary**

Run: `printf 'uci\nisready\nquit\n' | stockfish | grep -E "uciok|readyok|option name (Skill Level|UCI_Elo|UCI_LimitStrength)"`
Expected: `uciok`, `readyok` and the three option lines. Note the `UCI_Elo` min printed; it must be at most 1400, otherwise lower the Medium preset in `UCI` to the minimum and say so.

- [ ] **Step 4: Run the real-Stockfish tests**

Run: `mix test test/forkmate/bots/stockfish_test.exs`
Expected: PASS (all four levels return a legal move; mate-in-one found at max).

- [ ] **Step 5: Update docs**

README: in the MVP list add "Play against a Stockfish bot (choose difficulty and colour)", and add a short "Development" note: Stockfish is installed by `mise install` (or set `STOCKFISH_PATH`); credit: "Computer opponent powered by [Stockfish](https://stockfishchess.org) (GPL-3.0)".

CLAUDE.md, under "Core Domain & CQRS" add:

```
- **Bots** (`lib/forkmate/bots/`): a bot is a player id `bot:stockfish:<level>` (`Bots.Seat`). `Bots.Player` is a Commanded event handler that plays for bot seats via ordinary `MakeMove` commands; `Bots.Stockfish` (pool of UCI Port workers) implements the `Bots.Bot` behaviour, selected by `config :forkmate, :bot` (`FakeBot` in tests). Stockfish comes from `mise install` or `STOCKFISH_PATH`; tests tagged `:stockfish` are skipped when it is absent. `GameLive` locks the perspective to the human colour in bot games.
```

- [ ] **Step 6: Run the full precommit**

Run: `mix precommit`
Expected: PASS (compile with warnings as errors, format, credo --strict, clippy, cargo test, mix test). Fix any credo findings in the new files (alias order, module docs, function length). Then `git diff mix.lock` must be empty or intentional.

- [ ] **Step 7: Manual check**

Run `bin/dev`, open `http://localhost:4000`, start "Play vs computer" as Black on Medium: White's move must appear without any click; play a move, the bot replies, "Computer is thinking…" appears in between; try `?as=white` in the URL (ignored) and confirm there is no flip button.

- [ ] **Step 8: Commit**

```bash
git add mise.toml README.md CLAUDE.md
git commit -m "chore: provision Stockfish via mise and document the bot"
```
