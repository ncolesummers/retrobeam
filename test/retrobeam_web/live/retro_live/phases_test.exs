defmodule RetrobeamWeb.RetroLive.PhasesTest do
  use RetrobeamWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Retrobeam.AccountsFixtures
  import Retrobeam.RetrosFixtures

  alias Retrobeam.Repo
  alias Retrobeam.Retros
  alias Retrobeam.Retros.RetroSession

  setup :register_and_log_in_user

  setup %{scope: scope} do
    participant = user_fixture()
    retro = retro_fixture(scope)
    participation_fixture(retro, participant)

    participant_conn = Phoenix.ConnTest.build_conn() |> log_in_user(participant)

    %{retro: retro, participant: participant, participant_conn: participant_conn}
  end

  test "shows the phases with the current one marked", %{conn: conn, retro: retro} do
    {:ok, view, _html} = live(conn, ~p"/retros/#{retro}")

    assert has_element?(view, ~s|#phase-setup[aria-current="step"]|, "current phase")
    assert has_element?(view, ~s|#phase-collect[data-state="upcoming"]|, "upcoming")
    refute has_element?(view, ~s|#phase-collect[aria-current]|)
  end

  test "the facilitator advances and every participant sees it", %{
    conn: conn,
    participant_conn: participant_conn,
    retro: retro
  } do
    {:ok, facilitator, _html} = live(conn, ~p"/retros/#{retro}")
    {:ok, participant, _html} = live(participant_conn, ~p"/retros/#{retro}")

    refute has_element?(participant, "#next-phase")

    facilitator |> element("#next-phase", "Collect") |> render_click()

    assert has_element?(facilitator, ~s|#phase-collect[aria-current="step"]|)
    assert has_element?(facilitator, ~s|#phase-setup[data-state="done"]|, "completed")
    assert has_element?(participant, ~s|#phase-collect[aria-current="step"]|)
    assert has_element?(participant, "#retro-phase", "Collect")
    assert Repo.get!(RetroSession, retro.id).phase == :collect
  end

  test "a participant's forged event is rejected", %{participant_conn: conn, retro: retro} do
    {:ok, view, _html} = live(conn, ~p"/retros/#{retro}")

    assert render_click(view, "advance_phase", %{"from" => "setup"}) =~
             "Only the facilitator can do that."

    assert Repo.get!(RetroSession, retro.id).phase == :setup
  end

  test "a second click on a stale button does not skip a phase", %{conn: conn, retro: retro} do
    {:ok, view, _html} = live(conn, ~p"/retros/#{retro}")

    render_click(view, "advance_phase", %{"from" => "setup"})
    assert render_click(view, "advance_phase", %{"from" => "setup"}) =~ "already moved on"
    assert Repo.get!(RetroSession, retro.id).phase == :collect
  end

  test "the facilitator edits options during Setup and they lock afterwards", %{
    conn: conn,
    participant_conn: participant_conn,
    retro: retro
  } do
    {:ok, view, _html} = live(conn, ~p"/retros/#{retro}")
    {:ok, participant, _html} = live(participant_conn, ~p"/retros/#{retro}")

    refute has_element?(participant, "#options-form")
    assert has_element?(participant, "#retro-options", "5")

    assert view
           |> form("#options-form", retro_session: %{vote_limit: "25"})
           |> render_change() =~ "must be less than or equal to 20"

    view
    |> form("#options-form",
      retro_session: %{vote_limit: "7", anonymous: "true", allow_multiple_votes: "false"}
    )
    |> render_submit()

    assert render(view) =~ "Options saved."
    saved = Repo.get!(RetroSession, retro.id)
    assert {saved.vote_limit, saved.anonymous, saved.allow_multiple_votes} == {7, true, false}
    assert has_element?(participant, "#retro-options", "7")

    view |> element("#next-phase") |> render_click()
    refute has_element?(view, "#options-form")
    assert has_element?(view, "#retro-options", "7")
  end

  test "invalid options are shown on submit", %{conn: conn, retro: retro} do
    {:ok, view, _html} = live(conn, ~p"/retros/#{retro}")

    assert view
           |> form("#options-form", retro_session: %{vote_limit: "0"})
           |> render_submit() =~ "must be greater than or equal to 1"
  end

  test "saving options after Setup ended elsewhere shows an error", %{
    conn: conn,
    scope: scope,
    retro: retro
  } do
    {:ok, view, _html} = live(conn, ~p"/retros/#{retro}")
    {:ok, _} = Retros.update_options(scope, retro.id, %{"vote_limit" => "4"})

    # The retro moves on (say, from another tab) and an old form is submitted.
    {:ok, _} = Retros.advance_phase(scope, retro.id)

    assert render_submit(view, "save_options", %{"retro_session" => %{"vote_limit" => "3"}}) =~
             "Options lock once the retro leaves Setup."
  end

  test "Finish retro makes it read-only for everyone", %{
    conn: conn,
    participant_conn: participant_conn,
    scope: scope,
    retro: retro
  } do
    for _ <- 1..5, do: {:ok, _} = Retros.advance_phase(scope, retro.id)

    {:ok, view, _html} = live(conn, ~p"/retros/#{retro}")
    {:ok, participant, _html} = live(participant_conn, ~p"/retros/#{retro}")

    refute has_element?(view, "#next-phase")
    refute has_element?(participant, "#finish-retro")

    view |> element("#finish-retro") |> render_click()

    assert has_element?(view, "#retro-ended")
    assert has_element?(participant, "#retro-ended")
    refute has_element?(view, "#facilitator-controls")
    assert Repo.get!(RetroSession, retro.id).ended_at
    assert render_click(view, "finish", %{}) =~ "This retro is finished."
  end
end
