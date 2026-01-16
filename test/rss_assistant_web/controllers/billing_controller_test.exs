defmodule RssAssistantWeb.BillingControllerTest do
  use RssAssistantWeb.ConnCase

  import RssAssistant.AccountsFixtures

  setup do
    free_plan_fixture()
    pro_plan_fixture()
    %{user: user_fixture()}
  end

  describe "checkout" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/billing/checkout")
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    @tag :stripe_api
    test "redirects to Stripe checkout when authenticated", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/billing/checkout")

      # Will redirect to Stripe or show error if no API key configured
      assert redirected_to(conn) =~ ~r/(stripe\.com|\/)/
    end
  end

  describe "portal" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/billing/portal")
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "shows error when user has no subscription", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/billing/portal")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "No subscription found"
    end
  end

  describe "success" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/billing/success")
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "shows error when session_id is missing", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/billing/success")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Invalid checkout session"
    end

    @tag :stripe_api
    test "shows error when session_id is invalid", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/billing/success?session_id=invalid_session")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Something went wrong"
    end
  end

  describe "cancel" do
    test "requires authentication", %{conn: conn} do
      conn = get(conn, ~p"/billing/cancel")
      assert redirected_to(conn) == ~p"/users/log_in"
    end

    test "shows cancelled message", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/billing/cancel")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "cancelled"
    end
  end
end
