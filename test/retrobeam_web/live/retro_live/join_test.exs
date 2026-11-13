defmodule RetrobeamWeb.RetroLive.JoinTest do
  use RetrobeamWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Retrobeam.AccountsFixtures
  import Retrobeam.RetrosFixtures

  alias Retrobeam.Repo
  alias Retrobeam.Retros.RetroParticipation

  describe "signed out" do
    test "sends visitors to log in and remembers the join page", %{conn: conn} do
      conn = get(conn, ~p"/retros/join/ABC234")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert get_session(conn, :user_return_to) == "/retros/join/ABC234"
    end

    test "returns to the join page after logging in", %{conn: conn} do
      user = user_fixture() |> set_password()
      conn = conn |> init_test_session(%{user_return_to: "/retros/join/ABC234"})

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert redirected_to(conn) == "/retros/join/ABC234"
    end
  end

  describe "signed in" do
    setup :register_and_log_in_user

    setup do
      %{retro: retro_fixture(user_scope_fixture(), %{"title" => "Team retro"})}
    end

    test "joins with a valid code", %{conn: conn, retro: retro, user: user} do
      {:ok, view, _html} = live(conn, ~p"/retros/join")

      view |> form("#join-form", join: %{code: retro.join_code}) |> render_submit()

      assert_redirect(view, ~p"/retros/#{retro}")
      assert Repo.get_by!(RetroParticipation, user_id: user.id).role == :participant
    end

    test "pre-fills the code from the link and accepts lower case", %{conn: conn, retro: retro} do
      lower = String.downcase(retro.join_code)
      {:ok, view, _html} = live(conn, ~p"/retros/join/#{lower}")

      assert has_element?(view, ~s|#join_code[value="#{lower}"]|)

      view |> form("#join-form") |> render_submit()
      assert_redirect(view, ~p"/retros/#{retro}")
    end

    test "shows an inline error for an unknown code", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/retros/join")

      html = view |> form("#join-form", join: %{code: "ZZZZZZ"}) |> render_submit()

      assert html =~ "No retro has that code."
      assert has_element?(view, ~s|#join_code[aria-invalid="true"]|)

      html = view |> form("#join-form", join: %{code: "ZZZZZ"}) |> render_change()
      refute html =~ "No retro has that code."
    end

    test "says so when there have been too many failed attempts", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/retros/join")

      for _ <- 1..10, do: view |> form("#join-form", join: %{code: "ZZZZZZ"}) |> render_submit()

      html = view |> form("#join-form", join: %{code: "ZZZZZZ"}) |> render_submit()
      assert html =~ "Too many attempts."
    end

    test "ignores a join event without a code", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/retros/join")
      render_submit(view, "join", %{})
      assert has_element?(view, "#join-form")
    end

    test "joining again redirects without a second record", %{
      conn: conn,
      retro: retro,
      user: user
    } do
      participation_fixture(retro, user)
      {:ok, view, _html} = live(conn, ~p"/retros/join/#{retro.join_code}")

      view |> form("#join-form") |> render_submit()

      assert_redirect(view, ~p"/retros/#{retro}")
      assert Repo.aggregate(RetroParticipation, :count) == 2
    end

    test "opens ended retros read-only", %{conn: conn, retro: retro} do
      retro |> Ecto.Changeset.change(ended_at: DateTime.utc_now(:second)) |> Repo.update!()
      {:ok, view, _html} = live(conn, ~p"/retros/join/#{retro.join_code}")

      view |> form("#join-form") |> render_submit()
      assert_redirect(view, ~p"/retros/#{retro}")

      {:ok, show, _html} = live(conn, ~p"/retros/#{retro}")
      assert has_element?(show, "#retro-ended")
    end
  end
end
