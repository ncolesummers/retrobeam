defmodule Retrobeam.Retros.Changes.Phases do
  @moduledoc """
  Phase transitions, Setup options and finishing a retro. Facilitator only.
  See `Retrobeam.Retros.Changes` for the contract.
  """

  import Retrobeam.Retros.Changes

  alias Retrobeam.Repo
  alias Retrobeam.Retros.{Events, RetroSession}
  alias Retrobeam.Retros.RetroServer.State

  @doc "Moves to the next phase if the retro is still in `expected` (nil skips the check)."
  def advance(%State{retro: retro} = state, user_id, expected) do
    with :ok <- authorize_facilitator(state, user_id) do
      cond do
        expected not in [nil, retro.phase] ->
          {:error, :stale_phase}

        is_nil(RetroSession.next_phase(retro.phase)) ->
          {:error, :final_phase}

        true ->
          retro =
            retro
            |> RetroSession.advance_phase_changeset()
            |> Repo.update!()

          {:ok, retro, %{state | retro: retro}, [Events.phase_changed(retro)]}
      end
    end
  end

  @doc "Updates the Setup options. Only during Setup."
  def update_options(%State{retro: retro} = state, user_id, attrs) do
    with :ok <- authorize_facilitator(state, user_id),
         :ok <- locked_unless_setup(state),
         {:ok, retro} <- retro |> RetroSession.options_changeset(attrs) |> Repo.update() do
      {:ok, retro, %{state | retro: retro}, [Events.retro_updated(retro)]}
    end
  end

  @doc "Sets `ended_at`. Only in the Summary phase."
  def finish(%State{retro: retro} = state, user_id) do
    with :ok <- authorize_facilitator(state, user_id) do
      if retro.phase == :summary do
        retro = retro |> RetroSession.finish_changeset() |> Repo.update!()
        {:ok, retro, %{state | retro: retro}, [Events.retro_updated(retro)]}
      else
        {:error, :not_in_summary}
      end
    end
  end

  defp locked_unless_setup(state) do
    case require_phase(state, :setup) do
      :ok -> :ok
      {:error, :wrong_phase} -> {:error, :locked}
    end
  end
end
