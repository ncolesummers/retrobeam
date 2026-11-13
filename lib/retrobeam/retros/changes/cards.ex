defmodule Retrobeam.Retros.Changes.Cards do
  @moduledoc """
  Adding, editing and deleting cards. Any participant may add cards during
  Collect; only a card's author may edit or delete it, and only during
  Collect. See `Retrobeam.Retros.Changes` for the contract.
  """

  import Retrobeam.Retros.Changes

  alias Retrobeam.Repo
  alias Retrobeam.Retros.{Card, Events}
  alias Retrobeam.Retros.RetroServer.State

  @doc "Adds a card to a column. `attrs` holds `column_id` and `body`."
  def add(%State{retro: retro} = state, user_id, attrs) do
    with :ok <- authorize_participant(state, user_id),
         :ok <- require_phase(state, :collect),
         {:ok, column} <- fetch_column(state, attrs["column_id"] || attrs[:column_id]) do
      position = Enum.count(state.cards, fn {_id, card} -> card.retro_column_id == column.id end)

      changeset =
        Card.changeset(
          %Card{
            author_id: user_id,
            retro_column_id: column.id,
            retro_session_id: retro.id,
            position: position
          },
          attrs
        )

      with {:ok, card} <- Repo.insert(changeset) do
        card = Repo.preload(card, :author)
        {:ok, card, put_card(state, card), [Events.card_created(card)]}
      end
    end
  end

  @doc "Edits the body of the caller's own card."
  def update(%State{} = state, user_id, card_id, attrs) do
    with :ok <- authorize_participant(state, user_id),
         :ok <- require_phase(state, :collect),
         {:ok, card} <- fetch_own_card(state, user_id, card_id),
         {:ok, card} <- card |> Card.changeset(attrs) |> Repo.update() do
      {:ok, card, put_card(state, card), [Events.card_updated(card)]}
    end
  end

  @doc "Deletes the caller's own card."
  def delete(%State{} = state, user_id, card_id) do
    with :ok <- authorize_participant(state, user_id),
         :ok <- require_phase(state, :collect),
         {:ok, card} <- fetch_own_card(state, user_id, card_id) do
      Repo.delete!(card)
      state = %{state | cards: Map.delete(state.cards, card.id)}
      {:ok, card, state, [Events.card_deleted(card)]}
    end
  end

  defp put_card(state, card), do: %{state | cards: Map.put(state.cards, card.id, card)}

  defp fetch_column(%State{retro: retro}, column_id) do
    column_id = to_integer(column_id)

    case Enum.find(retro.columns, &(&1.id == column_id)) do
      nil -> {:error, :not_found}
      column -> {:ok, column}
    end
  end

  defp fetch_own_card(%State{cards: cards}, user_id, card_id) do
    case Map.fetch(cards, to_integer(card_id)) do
      {:ok, %Card{author_id: ^user_id} = card} -> {:ok, card}
      {:ok, %Card{}} -> {:error, :unauthorized}
      :error -> {:error, :not_found}
    end
  end

  defp to_integer(id) when is_integer(id), do: id

  defp to_integer(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp to_integer(_id), do: nil
end
