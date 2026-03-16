defmodule GameserverWeb.GameLiveTest do
  # async: false because tests interact with the global WorldServer
  use GameserverWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  describe "mount" do
    test "renders login form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")
      assert has_element?(view, "#login-form")
      assert has_element?(view, "#login-form input[name='login_form[username]']")
    end

    test "wraps content with Layouts.app", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")
      assert has_element?(view, "header.navbar")
    end
  end

  describe "validate" do
    test "shows error for username too short", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      html =
        view
        |> element("#login-form")
        |> render_change(%{login_form: %{username: "ab"}})

      assert html =~ "should be at least 3 character"
    end

    test "no error for valid username", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      html =
        view
        |> element("#login-form")
        |> render_change(%{login_form: %{username: "alice"}})

      refute html =~ "should be at least"
      refute html =~ "should be at most"
    end
  end

  describe "save" do
    test "joins world and redirects on valid username", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      view
      |> element("#login-form")
      |> render_submit(%{login_form: %{username: "testuser"}})

      {path, _flash} = assert_redirect(view)
      assert path =~ "/world?user_id="
    end

    test "shows validation error for invalid username", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/game")

      html =
        view
        |> element("#login-form")
        |> render_submit(%{login_form: %{username: "ab"}})

      assert html =~ "should be at least 3 character"
    end

    test "shows error when username is already taken", %{conn: conn} do
      unique_name = "taken#{System.unique_integer([:positive])}"
      {:ok, existing_user} = Gameserver.User.new(unique_name)
      {:ok, _position} = Gameserver.WorldServer.join_user(existing_user)

      {:ok, view, _html} = live(conn, ~p"/game")

      html =
        view
        |> element("#login-form")
        |> render_submit(%{login_form: %{username: unique_name}})

      # Should stay on the form (no redirect) and show an error
      refute_redirected(view, ~p"/world")
      assert html =~ "username not available", "Expected error message, got: #{html}"
    end
  end
end
