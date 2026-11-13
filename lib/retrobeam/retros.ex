defmodule Retrobeam.Retros do
  @moduledoc """
  The Retros context: creating, finding and listing retrospectives.

  Public functions take a `Retrobeam.Accounts.Scope` as their first argument
  and only return retros the scope's user takes part in.
  """

  import Ecto.Query, warn: false

  alias Retrobeam.Accounts.Scope
  alias Retrobeam.Repo
  alias Retrobeam.Retros.{Card, JoinCode, RetroParticipation, RetroServer, RetroSession}

  @join_code_attempts 5

  @doc """
  Returns a changeset for the "New retro" form.
  """
  def change_retro(%Scope{} = _scope, %RetroSession{} = session \\ %RetroSession{}, attrs \\ %{}) do
    RetroSession.form_changeset(session, attrs)
  end

  @doc """
  Creates a retro facilitated by the scope's user.

  The retro, its columns (from the chosen template) and the facilitator's
  participation are inserted in one transaction. If the generated join code
  is already taken, a new one is generated and the insert is retried.

  ## Options

    * `:generate_join_code` - a zero-arity function returning a join code.
      Defaults to `Retrobeam.Retros.JoinCode.generate/0`.

  """
  def create_retro(%Scope{user: user}, attrs, opts \\ []) do
    generate = Keyword.get(opts, :generate_join_code, &JoinCode.generate/0)
    insert_retro(user.id, attrs, generate, @join_code_attempts)
  end

  defp insert_retro(user_id, attrs, generate, attempts_left) do
    changeset = RetroSession.create_changeset(%RetroSession{}, attrs, user_id, generate.())

    case Repo.insert(changeset) do
      {:ok, session} ->
        {:ok, session}

      {:error, changeset} ->
        if attempts_left > 1 and join_code_taken?(changeset) do
          insert_retro(user_id, attrs, generate, attempts_left - 1)
        else
          {:error, changeset}
        end
    end
  end

  defp join_code_taken?(changeset) do
    Enum.any?(changeset.errors, fn {field, {_msg, opts}} ->
      field == :join_code and opts[:constraint] == :unique
    end)
  end

  @doc """
  Lists the retros the scope's user facilitates or has joined, newest first.
  """
  def list_retros(%Scope{user: user}) do
    Repo.all(
      from s in RetroSession,
        join: p in assoc(s, :participations),
        where: p.user_id == ^user.id,
        order_by: [desc: s.inserted_at, desc: s.id]
    )
  end

  @doc """
  Fetches a retro the scope's user takes part in, with its columns.

  Returns `{:error, :not_found}` when no retro has that id and
  `{:error, :not_participant, retro}` when the user has not joined it.
  """
  def fetch_retro(%Scope{user: user}, id) do
    with {:ok, id} <- cast_id(id),
         %RetroSession{} = session <- Repo.get(RetroSession, id) do
      if participant?(user.id, session.id) do
        {:ok, Repo.preload(session, :columns)}
      else
        {:error, :not_participant, session}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Joins the retro with `code` as a participant.

  The code is matched ignoring case and surrounding whitespace. Joining a
  retro again, or the facilitator joining their own retro, changes nothing.
  Ended retros can be joined; they open read-only.

  Returns `{:ok, retro}` or `{:error, :not_found}`.
  """
  def join_retro(%Scope{user: user}, code) do
    code = JoinCode.normalize(code)

    with true <- JoinCode.valid?(code),
         %RetroSession{} = session <- Repo.get_by(RetroSession, join_code: code) do
      {:ok, _participation} =
        %RetroParticipation{retro_session_id: session.id}
        |> RetroParticipation.changeset(%{
          user_id: user.id,
          role: :participant,
          joined_at: DateTime.utc_now(:second)
        })
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :retro_session_id])

      {:ok, session}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Moves the retro to its next phase. See `RetroServer.advance_phase/3`.
  """
  def advance_phase(%Scope{} = scope, retro_id, expected \\ nil),
    do: RetroServer.advance_phase(retro_id, scope, expected)

  @doc """
  Returns a changeset for the Setup options form.
  """
  def change_options(%RetroSession{} = retro, attrs \\ %{}),
    do: RetroSession.options_changeset(retro, attrs)

  @doc """
  Updates the retro's Setup options. See `RetroServer.update_options/3`.
  """
  def update_options(%Scope{} = scope, retro_id, attrs),
    do: RetroServer.update_options(retro_id, scope, attrs)

  @doc """
  Finishes the retro, making it read-only. See `RetroServer.finish/2`.
  """
  def finish_retro(%Scope{} = scope, retro_id), do: RetroServer.finish(retro_id, scope)

  @doc """
  Returns a changeset for a card form.
  """
  def change_card(%Card{} = card \\ %Card{}, attrs \\ %{}), do: Card.changeset(card, attrs)

  @doc """
  Adds a card during Collect. `attrs` holds `"column_id"` and `"body"`.
  See `RetroServer.add_card/3`.
  """
  def add_card(%Scope{} = scope, retro_id, attrs),
    do: RetroServer.add_card(retro_id, scope, attrs)

  @doc "Edits the scope's own card. See `RetroServer.update_card/4`."
  def update_card(%Scope{} = scope, retro_id, card_id, attrs),
    do: RetroServer.update_card(retro_id, scope, card_id, attrs)

  @doc "Deletes the scope's own card. See `RetroServer.delete_card/3`."
  def delete_card(%Scope{} = scope, retro_id, card_id),
    do: RetroServer.delete_card(retro_id, scope, card_id)

  @doc """
  Returns true when the scope's user is the retro's facilitator.
  """
  def facilitator?(%Scope{user: user}, %RetroSession{facilitator_id: facilitator_id}),
    do: user.id == facilitator_id

  defp participant?(user_id, session_id) do
    Repo.exists?(
      from p in RetroParticipation,
        where: p.user_id == ^user_id and p.retro_session_id == ^session_id
    )
  end

  defp cast_id(id) when is_integer(id), do: {:ok, id}

  defp cast_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp cast_id(_id), do: :error
end
