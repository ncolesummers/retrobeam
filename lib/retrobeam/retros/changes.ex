defmodule Retrobeam.Retros.Changes do
  @moduledoc """
  Shared rules for changes made through `Retrobeam.Retros.RetroServer`.

  Each change module (`Changes.Phases`, `Changes.Cards`, ...) exposes
  functions that take the server's `%RetroServer.State{}` first and return
  either `{:ok, reply, new_state, events}` or `{:error, reason}`. The server
  runs one change at a time, stores the new state and broadcasts the events
  in order. A change writes to Postgres before it returns `:ok`, so the
  events never announce something that was not saved.
  """

  alias Retrobeam.Retros.RetroServer.State
  alias Retrobeam.Retros.RetroSession

  @type result ::
          {:ok, reply :: term(), State.t(), [Retrobeam.Retros.Events.t()]}
          | {:error, term()}

  @doc "Fails unless `user_id` is the retro's facilitator and it has not ended."
  def authorize_facilitator(%State{retro: retro}, user_id) do
    cond do
      retro.facilitator_id != user_id -> {:error, :unauthorized}
      RetroSession.ended?(retro) -> {:error, :ended}
      true -> :ok
    end
  end

  @doc "Fails unless `user_id` takes part in the retro and it has not ended."
  def authorize_participant(%State{retro: retro} = state, user_id) do
    cond do
      not participant?(state, user_id) -> {:error, :unauthorized}
      RetroSession.ended?(retro) -> {:error, :ended}
      true -> :ok
    end
  end

  @doc "Fails with `{:error, :wrong_phase}` unless the retro is in `phase`."
  def require_phase(%State{retro: %RetroSession{phase: phase}}, phase), do: :ok
  def require_phase(%State{}, _phase), do: {:error, :wrong_phase}

  @doc "Returns true when `user_id` has a participation in the retro."
  def participant?(%State{participants: participants}, user_id),
    do: Enum.any?(participants, &(&1.user_id == user_id))
end
