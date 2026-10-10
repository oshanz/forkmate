defmodule Forkmate.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [ForkmateWeb.Telemetry, Forkmate.Repo] ++
        event_store_children() ++
        [
          {DNSCluster, query: Application.get_env(:forkmate, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: Forkmate.PubSub},
          # Start a worker by calling: Forkmate.Worker.start_link(arg)
          # {Forkmate.Worker, arg},
          # Start to serve requests, typically the last entry
          ForkmateWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Forkmate.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ForkmateWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp event_store_children do
    if Application.get_env(:forkmate, :start_event_store, true) do
      [
        Forkmate.CommandedApp,
        Forkmate.Games.Projections.GameProjection
      ]
    else
      []
    end
  end
end
