defmodule Retrobeam.Retros.Template do
  @moduledoc """
  Retro templates defined as plain data.

  A template is a named set of columns a retro starts with. The named
  templates have fixed columns; `:custom` lets the facilitator name 2 to 6
  columns of their own.

  Templates are not stored in the database. A retro stores its template key
  (see `keys/0`) and its own copy of the columns, so changing a template's
  columns here never changes an existing retro.

  Template keys are append-only. `keys/0` supplies the `Ecto.Enum` values of a
  retro's template field, and Ecto can't load a stored value it no longer
  lists, so renaming or removing a key breaks every retro that uses it.
  """

  @type key :: :start_stop_continue | :mad_sad_glad | :four_ls | :sailboat | :custom
  @type column :: %{name: String.t(), description: String.t() | nil, position: non_neg_integer()}
  @type t :: %{
          key: key(),
          name: String.t(),
          description: String.t(),
          columns: [column()]
        }
  @type custom_error ::
          :invalid_names
          | :too_few_columns
          | :too_many_columns
          | :blank_column_name
          | :column_name_too_long
          | :duplicate_column_names

  @min_custom_columns 2
  @max_custom_columns 6
  @max_column_name_length 40
  # The column name is stored as varchar(255), which Postgres measures in
  # codepoints. A name of 40 graphemes can be far more codepoints (emoji
  # sequences), so cap codepoints as well.
  @max_column_name_codepoints 255

  @named [
    {:start_stop_continue, "Start, Stop, Continue",
     "Decide what to begin, what to drop and what to keep.",
     [
       {"Start", "What should we begin doing?"},
       {"Stop", "What should we stop doing?"},
       {"Continue", "What is working that we should keep doing?"}
     ]},
    {:mad_sad_glad, "Mad, Sad, Glad", "Share how the sprint felt, from frustrations to wins.",
     [
       {"Mad", "What frustrated you?"},
       {"Sad", "What disappointed you?"},
       {"Glad", "What made you happy?"}
     ]},
    {:four_ls, "4Ls", "Reflect on what you liked, learned, lacked and longed for.",
     [
       {"Liked", "What did you enjoy?"},
       {"Learned", "What did you learn?"},
       {"Lacked", "What was missing?"},
       {"Longed For", "What do you wish we had?"}
     ]},
    {:sailboat, "Sailboat", "Map what moves the team forward and what holds it back.",
     [
       {"Wind", "What pushed us forward?"},
       {"Anchor", "What held us back?"},
       {"Rocks", "What risks are ahead?"},
       {"Island", "Where are we headed?"}
     ]}
  ]

  @templates Enum.map(@named, fn {key, name, description, columns} ->
               %{
                 key: key,
                 name: name,
                 description: description,
                 columns:
                   columns
                   |> Enum.with_index()
                   |> Enum.map(fn {{col_name, col_description}, position} ->
                     %{name: col_name, description: col_description, position: position}
                   end)
               }
             end)

  @named_keys Enum.map(@templates, & &1.key)

  @custom %{
    key: :custom,
    name: "Custom",
    description: "Name your own #{@min_custom_columns} to #{@max_custom_columns} columns.",
    columns: []
  }

  @doc """
  Returns the named templates in display order.

  Custom is not included because it has no fixed columns; see `custom/0`.
  """
  @spec all() :: [t()]
  def all, do: @templates

  @doc """
  Returns the Custom template's metadata. Its columns are empty until the
  facilitator names them with `columns/2`.
  """
  @spec custom() :: t()
  def custom, do: @custom

  @doc """
  Returns every template key, named templates first and `:custom` last.

  Use this for the `Ecto.Enum` values of a retro's template field.
  """
  @spec keys() :: [key()]
  def keys, do: @named_keys ++ [:custom]

  @doc """
  Fetches a template by key, or by its string form (as sent by a form).
  """
  @spec fetch(key() | String.t()) :: {:ok, t()} | :error
  def fetch(:custom), do: {:ok, @custom}

  def fetch(key) when is_atom(key) do
    case Enum.find(@templates, &(&1.key == key)) do
      nil -> :error
      template -> {:ok, template}
    end
  end

  def fetch(key) when is_binary(key) do
    case Enum.find(keys(), &(Atom.to_string(&1) == key)) do
      nil -> :error
      atom -> fetch(atom)
    end
  end

  def fetch(_key), do: :error

  @doc """
  Returns the columns of a named template.

  Raises `ArgumentError` for `:custom` (use `columns/2`) and for unknown keys.
  """
  @spec columns(key()) :: [column()]
  def columns(key) when key in [:custom, "custom"] do
    raise ArgumentError, "the custom template has no fixed columns, use columns(:custom, names)"
  end

  def columns(key) do
    case fetch(key) do
      {:ok, template} -> template.columns
      :error -> raise ArgumentError, "unknown retro template: #{inspect(key)}"
    end
  end

  @doc """
  Builds columns for a template.

  For `:custom`, `names` must be a list of #{@min_custom_columns} to
  #{@max_custom_columns} column names. Names are normalized (see
  `normalize_name/1`), must not be blank, must be at most
  #{@max_column_name_length} characters and must be unique ignoring case. For a
  named template, `names` is ignored.

  ## Examples

      iex> Retrobeam.Retros.Template.columns(:custom, ["Wins", " Puzzles "])
      {:ok, [%{name: "Wins", description: nil, position: 0}, %{name: "Puzzles", description: nil, position: 1}]}

      iex> Retrobeam.Retros.Template.columns(:custom, ["Only one"])
      {:error, :too_few_columns}

  """
  @spec columns(key() | String.t(), [String.t()]) ::
          {:ok, [column()]} | {:error, custom_error() | :unknown_template}
  def columns(key, names) when key in [:custom, "custom"] do
    with :ok <- validate_list(names),
         names = Enum.map(names, &normalize_name/1),
         :ok <- validate_count(names),
         :ok <- validate_each(names),
         :ok <- validate_unique(names) do
      columns =
        names
        |> Enum.with_index()
        |> Enum.map(fn {name, position} ->
          %{name: name, description: nil, position: position}
        end)

      {:ok, columns}
    end
  end

  def columns(key, _names) do
    case fetch(key) do
      {:ok, template} -> {:ok, template.columns}
      :error -> {:error, :unknown_template}
    end
  end

  @doc """
  Returns a message for a `columns/2` error, suitable for showing to a user.
  """
  @spec error_message(custom_error() | :unknown_template) :: String.t()
  def error_message(:invalid_names), do: "Column names must be text."

  def error_message(:too_few_columns),
    do: "Add at least #{@min_custom_columns} columns."

  def error_message(:too_many_columns),
    do: "Use at most #{@max_custom_columns} columns."

  def error_message(:blank_column_name), do: "Every column needs a name."

  def error_message(:column_name_too_long),
    do: "Column names can be at most #{@max_column_name_length} characters."

  def error_message(:duplicate_column_names), do: "Column names must be different."
  def error_message(:unknown_template), do: "Choose a template."

  @doc """
  Normalizes a column name: converts it to Unicode NFC, removes invisible
  format characters such as zero-width spaces, and trims whitespace.

  Zero-width joiners and non-joiners are kept, because emoji sequences and
  some scripts need them to render correctly. The blank and duplicate checks
  ignore them instead.

  ## Examples

      iex> Retrobeam.Retros.Template.normalize_name(" Wins\u200B ")
      "Wins"

  """
  @spec normalize_name(String.t()) :: String.t()
  def normalize_name(name) when is_binary(name) do
    name
    |> to_nfc()
    |> String.replace(~r/(?![\x{200C}\x{200D}])\p{Cf}/u, "")
    |> String.trim()
  end

  defp to_nfc(name) do
    case :unicode.characters_to_nfc_binary(name) do
      normalized when is_binary(normalized) -> normalized
      _invalid -> name
    end
  end

  # The form of a name used to compare names: no format characters at all,
  # lowercased.
  defp comparable(name), do: name |> String.replace(~r/\p{Cf}/u, "") |> String.downcase()

  @doc "The fewest columns a custom template may have."
  def min_custom_columns, do: @min_custom_columns

  @doc "The most columns a custom template may have."
  def max_custom_columns, do: @max_custom_columns

  @doc "The longest a column name may be, in characters."
  def max_column_name_length, do: @max_column_name_length

  defp validate_list(names) when is_list(names) do
    if Enum.all?(names, &is_binary/1), do: :ok, else: {:error, :invalid_names}
  end

  defp validate_list(_names), do: {:error, :invalid_names}

  defp validate_count(names) when length(names) < @min_custom_columns,
    do: {:error, :too_few_columns}

  defp validate_count(names) when length(names) > @max_custom_columns,
    do: {:error, :too_many_columns}

  defp validate_count(_names), do: :ok

  defp validate_each(names) do
    cond do
      Enum.any?(names, &(comparable(&1) == "")) ->
        {:error, :blank_column_name}

      Enum.any?(names, &too_long?/1) ->
        {:error, :column_name_too_long}

      true ->
        :ok
    end
  end

  defp too_long?(name) do
    String.length(name) > @max_column_name_length or
      length(String.to_charlist(name)) > @max_column_name_codepoints
  end

  defp validate_unique(names) do
    downcased = Enum.map(names, &comparable/1)

    if length(Enum.uniq(downcased)) == length(downcased),
      do: :ok,
      else: {:error, :duplicate_column_names}
  end
end
