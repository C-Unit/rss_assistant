defmodule RssAssistantWeb.BillingController do
  use RssAssistantWeb, :controller
  require Logger

  alias RssAssistant.Billing
  alias RssAssistant.Billing.StripeService
  alias RssAssistant.Accounts

  @doc """
  Shows the pricing page with available plans.
  """
  def pricing(conn, _params) do
    plans = Accounts.list_plans()
    current_user = conn.assigns[:current_user]

    subscription =
      if current_user do
        Billing.get_subscription_by_user_id(current_user.id)
      else
        nil
      end

    render(conn, :pricing,
      plans: plans,
      current_user: current_user,
      subscription: subscription
    )
  end

  @doc """
  Creates a Stripe Checkout session and redirects to Stripe.
  """
  def create_checkout_session(conn, %{"plan" => plan_name}) do
    current_user = conn.assigns.current_user

    # Build success and cancel URLs
    success_url = url(~p"/billing/success?session_id={CHECKOUT_SESSION_ID}")
    cancel_url = url(~p"/billing/pricing")

    case StripeService.create_checkout_session(
           current_user,
           plan_name,
           success_url,
           cancel_url
         ) do
      {:ok, session} ->
        redirect(conn, external: session.url)

      {:error, error} ->
        Logger.error("Failed to create checkout session: #{inspect(error)}")

        conn
        |> put_flash(:error, "Failed to initiate checkout. Please try again.")
        |> redirect(to: ~p"/billing/pricing")
    end
  end

  @doc """
  Success page after completing checkout.
  """
  def success(conn, %{"session_id" => session_id}) do
    current_user = conn.assigns.current_user

    # Retrieve the session to get details
    case Stripe.Session.retrieve(session_id, expand: ["subscription"]) do
      {:ok, session} ->
        # The subscription should be created via webhook, but we can display success
        render(conn, :success, session: session)

      {:error, _error} ->
        conn
        |> put_flash(:error, "Unable to verify checkout session.")
        |> redirect(to: ~p"/")
    end
  end

  def success(conn, _params) do
    # Redirect if no session_id
    redirect(conn, to: ~p"/")
  end

  @doc """
  Shows the subscription management page.
  """
  def manage(conn, _params) do
    current_user = conn.assigns.current_user
    subscription = Billing.get_subscription_by_user_id(current_user.id)

    render(conn, :manage,
      subscription: subscription,
      current_user: current_user
    )
  end

  @doc """
  Redirects to Stripe's customer portal for managing subscription.
  """
  def portal(conn, _params) do
    current_user = conn.assigns.current_user
    return_url = url(~p"/billing/manage")

    case StripeService.create_billing_portal_session(current_user, return_url) do
      {:ok, session} ->
        redirect(conn, external: session.url)

      {:error, :no_subscription} ->
        conn
        |> put_flash(:error, "You don't have an active subscription.")
        |> redirect(to: ~p"/billing/pricing")

      {:error, error} ->
        Logger.error("Failed to create portal session: #{inspect(error)}")

        conn
        |> put_flash(:error, "Failed to access billing portal. Please try again.")
        |> redirect(to: ~p"/billing/manage")
    end
  end

  @doc """
  Cancels a subscription at the end of the billing period.
  """
  def cancel(conn, _params) do
    current_user = conn.assigns.current_user

    case Billing.get_subscription_by_user_id(current_user.id) do
      nil ->
        conn
        |> put_flash(:error, "No active subscription found.")
        |> redirect(to: ~p"/billing/manage")

      subscription ->
        case StripeService.cancel_subscription(subscription) do
          {:ok, _stripe_subscription} ->
            conn
            |> put_flash(:info, "Your subscription will be canceled at the end of the billing period.")
            |> redirect(to: ~p"/billing/manage")

          {:error, error} ->
            Logger.error("Failed to cancel subscription: #{inspect(error)}")

            conn
            |> put_flash(:error, "Failed to cancel subscription. Please try again.")
            |> redirect(to: ~p"/billing/manage")
        end
    end
  end

  @doc """
  Reactivates a subscription that was set to cancel.
  """
  def reactivate(conn, _params) do
    current_user = conn.assigns.current_user

    case Billing.get_subscription_by_user_id(current_user.id) do
      nil ->
        conn
        |> put_flash(:error, "No subscription found.")
        |> redirect(to: ~p"/billing/manage")

      subscription ->
        case StripeService.reactivate_subscription(subscription) do
          {:ok, _stripe_subscription} ->
            conn
            |> put_flash(:info, "Your subscription has been reactivated.")
            |> redirect(to: ~p"/billing/manage")

          {:error, error} ->
            Logger.error("Failed to reactivate subscription: #{inspect(error)}")

            conn
            |> put_flash(:error, "Failed to reactivate subscription. Please try again.")
            |> redirect(to: ~p"/billing/manage")
        end
    end
  end
end
