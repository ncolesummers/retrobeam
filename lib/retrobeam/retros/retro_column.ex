defmodule Retrobeam.Retros.RetroColumn do
  @moduledoc """
  A column on a retro board. Each retro keeps its own copy of the columns
  from its template.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "retro_columns" do
    field :name, :string
    field :description, :string
    field :position, :integer

    belongs_to :retro_session, Retrobeam.Retros.RetroSession

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(column, attrs) do
    column
    |> cast(attrs, [:name, :description, :position])
    |> validate_required([:name, :position])
    |> validate_length(:name, max: Retrobeam.Retros.Template.max_column_name_length())
    |> validate_number(:position, greater_than_or_equal_to: 0)
  end
end
