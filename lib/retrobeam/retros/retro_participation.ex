defmodule Retrobeam.Retros.RetroParticipation do
  @moduledoc """
  Links a user to a retro they facilitate or have joined.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "retro_participations" do
    field :role, Ecto.Enum, values: [:facilitator, :participant], default: :participant
    field :joined_at, :utc_datetime

    belongs_to :user, Retrobeam.Accounts.User
    belongs_to :retro_session, Retrobeam.Retros.RetroSession

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(participation, attrs) do
    participation
    |> cast(attrs, [:role, :joined_at, :user_id])
    |> validate_required([:role, :joined_at, :user_id])
    |> unique_constraint([:user_id, :retro_session_id])
  end
end
