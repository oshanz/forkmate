defmodule Forkmate.EventStore do
  @moduledoc """
  Postgres-backed event store for Forkmate.
  """

  use EventStore, otp_app: :forkmate
end
