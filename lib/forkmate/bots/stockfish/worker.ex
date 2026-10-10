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

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, nil, name: Keyword.fetch!(opts, :name))

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
      nil -> {:error, :stockfish_not_found}
      path -> open_port(path)
    end
  end

  defp open_port(path) do
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

  defp send_commands(port, commands) do
    Port.command(port, Enum.map(commands, &[&1, ?\n]))
    :ok
  rescue
    ArgumentError -> {:error, :port_closed}
  end

  defp await_bestmove(port) do
    case await_line(port, &(UCI.parse_bestmove(&1) != :ignore), @search_timeout) do
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
