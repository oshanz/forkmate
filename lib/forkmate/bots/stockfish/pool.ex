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
