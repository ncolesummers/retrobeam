defmodule Retrobeam.Repo.Migrations.CreateRetroSessions do
  use Ecto.Migration

  def change do
    create table(:retro_sessions) do
      add :title, :string, null: false
      add :template, :string, null: false
      add :phase, :string, null: false, default: "setup"
      add :join_code, :string, null: false
      add :vote_limit, :integer, null: false, default: 5
      add :allow_multiple_votes, :boolean, null: false, default: true
      add :anonymous, :boolean, null: false, default: false
      add :hide_cards_during_collect, :boolean, null: false, default: false
      add :topic_timebox_seconds, :integer, null: false, default: 300
      add :started_at, :utc_datetime
      add :ended_at, :utc_datetime
      add :facilitator_id, references(:users, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:retro_sessions, [:join_code])
    create index(:retro_sessions, [:facilitator_id])

    create constraint(:retro_sessions, :vote_limit_range, check: "vote_limit BETWEEN 1 AND 20")

    create constraint(:retro_sessions, :topic_timebox_positive,
             check: "topic_timebox_seconds > 0"
           )

    create table(:retro_columns) do
      add :name, :string, null: false
      add :description, :text
      add :position, :integer, null: false

      add :retro_session_id, references(:retro_sessions, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:retro_columns, [:retro_session_id, :position])

    create table(:retro_participations) do
      add :role, :string, null: false, default: "participant"
      add :joined_at, :utc_datetime, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :retro_session_id, references(:retro_sessions, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:retro_participations, [:user_id, :retro_session_id])
    create index(:retro_participations, [:retro_session_id])
  end
end
