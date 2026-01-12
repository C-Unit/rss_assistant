defmodule RssAssistantWeb.BillingController do
  use RssAssistantWeb, :controller

  alias RssAssistant.Billing

  def checkout(conn, _params) do
    user = conn.assigns.current_user

    case Billing.create_checkout_session(user) do
      {:ok, url} ->
        redirect(conn, external: url)

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Unable to start checkout. Please try again.")
        |> redirect(to: ~p"/")
    end
  end

  def portal(conn, _params) do
    user = conn.assigns.current_user

    case Billing.create_portal_session(user) do
      {:ok, url} ->
        redirect(conn, external: url)

      {:error, :no_customer} ->
        conn
        |> put_flash(:error, "No subscription found. Please upgrade first.")
        |> redirect(to: ~p"/")

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Unable to open billing portal. Please try again.")
        |> redirect(to: ~p"/")
    end
  end

  def success(conn, %{"session_id" => session_id}) do
    user = conn.assigns.current_user

    case Billing.fulfill_checkout(session_id, user) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Thank you for subscribing! Your Pro plan is now active.")
        |> redirect(to: ~p"/")

      {:error, reason} ->
        conn
        |> put_flash(:error, "Something went wrong activating your subscription: #{reason}")
        |> redirect(to: ~p"/")
    end
  end

  def success(conn, _params) do
    conn
    |> put_flash(:error, "Invalid checkout session.")
    |> redirect(to: ~p"/")
  end

  def cancel(conn, _params) do
    conn
    |> put_flash(:info, "Checkout cancelled.")
    |> redirect(to: ~p"/")
  end
end
