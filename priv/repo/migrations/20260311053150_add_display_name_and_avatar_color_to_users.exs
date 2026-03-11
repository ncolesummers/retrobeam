defmodule Retrobeam.Repo.Migrations.AddDisplayNameAndAvatarColorToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :display_name, :string, null: false
      add :avatar_color, :string, null: false
    end
  end
end
