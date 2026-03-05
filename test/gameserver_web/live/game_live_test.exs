defmodule GameserverWeb.GameLiveTest do
  # async: false because tests interact with the global WorldServer
  use GameserverWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "mount" do
    test "renders login form", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/game")
      assert html =~ "Username"
      assert has_element?(view, "input[name='login_form[username]']")
    end
  end

  describe "validate" do
    test "shows error for username too short", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      html =
        view
        |> element("form")
        |> render_change(%{login_form: %{username: "ab"}})

      assert html =~ "should be at least 3 character"
    end

    test "no error for valid username", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      html =
        view
        |> element("form")
        |> render_change(%{login_form: %{username: "alice"}})

      refute html =~ "should be at least"
      refute html =~ "should be at most"
    end
  end

  describe "save" do
    test "joins world and redirects on valid username", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      view
      |> element("form")
      |> render_submit(%{login_form: %{username: "testuser"}})

      {path, _flash} = assert_redirect(view)
      assert path =~ "/world?user_id="
    end

    test "shows validation error for invalid username", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      html =
        view
        |> element("form")
        |> render_submit(%{login_form: %{username: "ab"}})

      assert html =~ "should be at least 3 character"
    end
  end
end
