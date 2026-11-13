defmodule Retrobeam.Repo.Migrations.CreateCards do
  use Ecto.Migration

  def change do
    create table(:cards) do
      add :body, :text, null: false
      add :position, :integer, null: false, default: 0
      add :author_id, references(:users, on_delete: :nilify_all)
      add :retro_column_id, references(:retro_columns, on_delete: :delete_all), null: false
      add :retro_session_id, references(:retro_sessions, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:cards, [:retro_session_id])
    create index(:cards, [:retro_column_id])
    create index(:cards, [:author_id])
  end
end
