defmodule Retrobeam.Retros.Card do
  @moduledoc """
  A card on a retro board, written by a participant into one column.

  The author is kept even in anonymous retros so authors can edit their own
  cards; anonymous retros just never render it for anyone else.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @max_body_length 500

  schema "cards" do
    field :body, :string
    field :position, :integer, default: 0

    belongs_to :author, Retrobeam.Accounts.User
    belongs_to :column, Retrobeam.Retros.RetroColumn, foreign_key: :retro_column_id
    belongs_to :retro_session, Retrobeam.Retros.RetroSession

    timestamps(type: :utc_datetime)
  end

  @doc "The longest card body allowed, in characters."
  def max_body_length, do: @max_body_length

  @doc "Changeset for a card's body, used to create and edit cards."
  def changeset(card, attrs) do
    card
    |> cast(attrs, [:body], empty_values: [])
    |> update_change(:body, &String.trim/1)
    |> validate_required([:body], message: "can't be blank")
    |> validate_length(:body, min: 1, max: @max_body_length)
  end
end
