ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Forkmate.Repo, :manual)

unless Forkmate.Bots.Stockfish.available?() do
  ExUnit.configure(exclude: [:stockfish])
end
