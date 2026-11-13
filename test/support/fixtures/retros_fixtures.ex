defmodule Retrobeam.RetrosFixtures do
  @moduledoc """
  Test helpers for creating retros.
  """

  alias Retrobeam.Repo
  alias Retrobeam.Retros
  alias Retrobeam.Retros.RetroParticipation

  def valid_retro_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{"title" => "Sprint retro", "template" => "start_stop_continue"})
  end

  @doc "Creates a retro facilitated by the scope's user."
  def retro_fixture(scope, attrs \\ %{}) do
    {:ok, retro} = Retros.create_retro(scope, valid_retro_attributes(attrs))
    retro
  end

  @doc "Adds `user` to `retro` as a participant."
  def participation_fixture(retro, user, role \\ :participant) do
    Repo.insert!(%RetroParticipation{
      retro_session_id: retro.id,
      user_id: user.id,
      role: role,
      joined_at: DateTime.utc_now(:second)
    })
  end
end
