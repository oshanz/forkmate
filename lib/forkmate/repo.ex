defmodule Forkmate.Repo do
  use Ecto.Repo,
    otp_app: :forkmate,
    adapter: Ecto.Adapters.Postgres
end
