defmodule Forkmate.Bots.UnavailableBot do
  @moduledoc false
  @behaviour Forkmate.Bots.Bot

  @impl true
  def available?, do: false

  @impl true
  def best_move(_fen, _level), do: {:error, :unavailable}
end
