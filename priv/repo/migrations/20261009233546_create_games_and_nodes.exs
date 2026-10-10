defmodule Forkmate.Repo.Migrations.CreateGamesAndNodes do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:projection_versions, primary_key: false) do
      add :projection_name, :text, primary_key: true
      add :last_seen_event_number, :bigint

      timestamps(type: :naive_datetime_usec)
    end

    create table(:games, primary_key: false) do
      add :id, :string, primary_key: true
      add :root_node_id, :string, null: false
      add :current_node_id, :string
      add :white_player_id, :string, null: false
      add :black_player_id, :string, null: false
      add :current_fen, :text, null: false
      add :status, :string, default: "active", null: false
      add :winner, :string
      add :end_reason, :string
      add :draw_offered_by, :string

      timestamps(type: :utc_datetime)
    end

    create table(:game_nodes, primary_key: false) do
      add :id, :string, primary_key: true
      add :game_id, references(:games, type: :string, on_delete: :delete_all), null: false
      add :parent_id, :string
      add :ply, :integer, null: false
      add :san, :string
      add :fen, :text, null: false
      add :mover, :string
      add :status, :string, default: "open", null: false
      add :from_square, :string
      add :to_square, :string
      add :promotion, :string
      add :check_square, :string

      timestamps(type: :utc_datetime)
    end

    create index(:game_nodes, [:game_id])
    create index(:game_nodes, [:game_id, :parent_id])
    create index(:game_nodes, [:game_id, :ply])
  end
end
