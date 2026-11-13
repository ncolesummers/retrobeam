defmodule Retrobeam.Retros.RetroSession do
  @moduledoc """
  A retrospective: its template, phase, options and join code.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Retrobeam.Retros.{RetroColumn, RetroParticipation, Template}

  @phases [:setup, :collect, :group, :vote, :discuss, :summary]
  @max_title_length 100

  schema "retro_sessions" do
    field :title, :string
    field :template, Ecto.Enum, values: Template.keys()
    field :phase, Ecto.Enum, values: @phases, default: :setup
    field :join_code, :string
    field :vote_limit, :integer, default: 5
    field :allow_multiple_votes, :boolean, default: true
    field :anonymous, :boolean, default: false
    field :hide_cards_during_collect, :boolean, default: false
    field :topic_timebox_seconds, :integer, default: 300
    field :started_at, :utc_datetime
    field :ended_at, :utc_datetime

    # Column names typed by the facilitator for the Custom template.
    field :custom_columns, {:array, :string}, virtual: true, default: []

    belongs_to :facilitator, Retrobeam.Accounts.User
    has_many :columns, RetroColumn, preload_order: [asc: :position]
    has_many :participations, RetroParticipation

    timestamps(type: :utc_datetime)
  end

  @doc "The phases of a retro, in order."
  def phases, do: @phases

  @type phase :: :setup | :collect | :group | :vote | :discuss | :summary
  @type t :: %__MODULE__{}

  @doc """
  The phase after `phase`, or nil for the last phase.

      iex> Retrobeam.Retros.RetroSession.next_phase(:setup)
      :collect
      iex> Retrobeam.Retros.RetroSession.next_phase(:summary)
      nil
  """
  def next_phase(phase) do
    case Enum.drop_while(@phases, &(&1 != phase)) do
      [^phase, next | _] -> next
      _ -> nil
    end
  end

  @doc "A human-readable label for a phase."
  def phase_label(:setup), do: "Setup"
  def phase_label(:collect), do: "Collect"
  def phase_label(:group), do: "Group"
  def phase_label(:vote), do: "Vote"
  def phase_label(:discuss), do: "Discuss"
  def phase_label(:summary), do: "Summary"

  @doc "Returns true once the retro has been finished."
  def ended?(%__MODULE__{ended_at: ended_at}), do: not is_nil(ended_at)

  @doc """
  Changeset for the "New retro" form: title, template and, for the Custom
  template, the column names. Validates without building columns.
  """
  def form_changeset(session, attrs) do
    session
    |> cast(attrs, [:title, :template])
    # Keep blank names so they are reported instead of silently dropped.
    |> cast(attrs, [:custom_columns], empty_values: [])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:title, :template], message: "can't be blank")
    |> validate_length(:title, max: @max_title_length)
    |> validate_custom_columns()
  end

  @doc """
  Changeset that creates a retro for `facilitator_id` with `join_code`.

  Builds the retro's columns from its template and the facilitator's
  participation, so a single insert writes all three tables in one
  transaction.
  """
  def create_changeset(session, attrs, facilitator_id, join_code) do
    changeset =
      session
      |> form_changeset(attrs)
      |> put_change(:facilitator_id, facilitator_id)
      |> put_change(:join_code, join_code)
      |> unique_constraint(:join_code)

    if changeset.valid? do
      changeset
      |> put_assoc(:columns, build_columns(changeset))
      |> put_assoc(:participations, [
        %RetroParticipation{
          user_id: facilitator_id,
          role: :facilitator,
          joined_at: DateTime.utc_now(:second)
        }
      ])
    else
      changeset
    end
  end

  @doc """
  Changeset for the facilitator's Setup options.
  """
  def options_changeset(session, attrs) do
    session
    |> cast(attrs, [:vote_limit, :allow_multiple_votes, :anonymous, :hide_cards_during_collect])
    |> validate_required([:vote_limit])
    |> validate_number(:vote_limit, greater_than_or_equal_to: 1, less_than_or_equal_to: 20)
    |> check_constraint(:vote_limit, name: :vote_limit_range, message: "must be between 1 and 20")
  end

  @doc """
  Changeset that moves the retro to its next phase. Leaving Setup records
  `started_at`.
  """
  def advance_phase_changeset(%__MODULE__{phase: phase} = session) do
    next = next_phase(phase) || raise ArgumentError, "#{inspect(phase)} is the last phase"
    changeset = change(session, phase: next)

    if phase == :setup,
      do: put_change(changeset, :started_at, DateTime.utc_now(:second)),
      else: changeset
  end

  @doc "Changeset that finishes the retro."
  def finish_changeset(session), do: change(session, ended_at: DateTime.utc_now(:second))

  defp validate_custom_columns(changeset) do
    case get_field(changeset, :template) do
      :custom ->
        case Template.columns(:custom, get_field(changeset, :custom_columns) || []) do
          {:ok, _columns} ->
            changeset

          {:error, reason} ->
            add_error(changeset, :custom_columns, Template.error_message(reason))
        end

      _ ->
        changeset
    end
  end

  defp build_columns(changeset) do
    template = get_field(changeset, :template)

    {:ok, columns} = Template.columns(template, get_field(changeset, :custom_columns) || [])

    Enum.map(columns, &struct(RetroColumn, &1))
  end
end
