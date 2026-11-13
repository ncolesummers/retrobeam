defmodule Retrobeam.Retros.SchemasTest do
  use Retrobeam.DataCase, async: true

  alias Retrobeam.Retros.{RetroColumn, RetroParticipation}

  test "RetroColumn.changeset/2 validates name and position" do
    assert RetroColumn.changeset(%RetroColumn{}, %{name: "Wins", position: 0}).valid?

    changeset =
      RetroColumn.changeset(%RetroColumn{}, %{name: String.duplicate("a", 41), position: -1})

    errors = errors_on(changeset)
    assert errors.name == ["should be at most 40 character(s)"]
    assert errors.position == ["must be greater than or equal to 0"]
  end

  test "RetroParticipation.changeset/2 requires a user and join time" do
    changeset = RetroParticipation.changeset(%RetroParticipation{}, %{})
    errors = errors_on(changeset)
    assert errors.user_id == ["can't be blank"]
    assert errors.joined_at == ["can't be blank"]

    changeset =
      RetroParticipation.changeset(%RetroParticipation{}, %{
        user_id: 1,
        joined_at: DateTime.utc_now(:second)
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_field(changeset, :role) == :participant
  end
end
