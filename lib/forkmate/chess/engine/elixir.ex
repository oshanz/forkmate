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
