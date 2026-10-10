defmodule Forkmate.CommandedApp do
  @moduledoc """
  Commanded application for Forkmate.
  """
  use Commanded.Application,
    otp_app: :forkmate,
    event_store: [
      adapter: Commanded.EventStore.Adapters.EventStore,
      event_store: Forkmate.EventStore
    ]

  router(Forkmate.Games.Router)
end
