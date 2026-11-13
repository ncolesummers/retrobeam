defmodule RetrobeamWeb.RetroLive.NewTest do
  use RetrobeamWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Retrobeam.Repo
  alias Retrobeam.Retros.RetroSession

  setup :register_and_log_in_user

  test "shows every template with a column preview", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/retros/new")

    for key <- ~w(start_stop_continue mad_sad_glad four_ls sailboat custom) do
      assert has_element?(view, "#retro_template_#{key}")
    end

    assert html =~ "Longed For"
    assert has_element?(view, "#retro_template_start_stop_continue[checked]")
    refute has_element?(view, "#custom-columns")
  end

  test "creates a retro and opens it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/retros/new")

    view
    |> form("#retro-form", retro: %{title: "Sprint 9", template: "four_ls"})
    |> render_submit()

    retro = Repo.get_by!(RetroSession, title: "Sprint 9")
    assert_redirect(view, ~p"/retros/#{retro}")
    assert retro.template == :four_ls
  end

  test "shows a title error", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/retros/new")

    html =
      view
      |> form("#retro-form", retro: %{title: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
    assert Repo.aggregate(RetroSession, :count) == 0
  end

  test "custom template: add, remove and validate columns", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/retros/new")

    view |> form("#retro-form", retro: %{template: "custom"}) |> render_change()
    assert has_element?(view, "#custom-columns")
    assert has_element?(view, "#retro_custom_columns_2")
    refute render(view) =~ "Every column needs a name."

    view |> element(~s|button[phx-value-index="2"]|) |> render_click()
    refute has_element?(view, "#retro_custom_columns_2")
    refute has_element?(view, "button[phx-value-index]")

    for _ <- 1..4, do: view |> element("#add-column") |> render_click()
    assert has_element?(view, "#retro_custom_columns_5")
    refute has_element?(view, "#add-column")

    html =
      view
      |> form("#retro-form", retro: %{custom_columns: ["Keep", "keep", "", "", "", ""]})
      |> render_change()

    assert html =~ "Every column needs a name."
  end

  test "custom template: creates the retro with the typed columns", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/retros/new")

    view |> form("#retro-form", retro: %{template: "custom"}) |> render_change()
    view |> element(~s|button[phx-value-index="2"]|) |> render_click()

    view
    |> form("#retro-form", retro: %{title: "Custom one", custom_columns: ["Wins", "Ideas"]})
    |> render_submit()

    retro = RetroSession |> Repo.get_by!(title: "Custom one") |> Repo.preload(:columns)
    assert_redirect(view, ~p"/retros/#{retro}")
    assert Enum.map(retro.columns, & &1.name) == ["Wins", "Ideas"]
  end

  test "custom template: shows errors on submit", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/retros/new")

    view |> form("#retro-form", retro: %{template: "custom"}) |> render_change()

    html =
      view
      |> form("#retro-form", retro: %{title: "Bad", custom_columns: ["A", "a", "B"]})
      |> render_submit()

    assert html =~ "Column names must be different."
  end

  test "keeps custom column names when switching templates", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/retros/new")

    view
    |> form("#retro-form", retro: %{template: "custom"})
    |> render_change(%{
      "retro" => %{"template" => "custom", "custom_columns" => ["Up", "Down", ""]}
    })

    view |> form("#retro-form", retro: %{template: "sailboat"}) |> render_change()
    view |> form("#retro-form", retro: %{template: "custom"}) |> render_change()

    assert has_element?(view, ~s|#retro_custom_columns_0[value="Up"]|)
  end
end
