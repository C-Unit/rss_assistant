defmodule RssAssistantWeb.BillingController do
  use RssAssistantWeb, :controller
  require Logger

  alias RssAssistant.Accounts
  alias RssAssistant.Billing
  alias RssAssistant.Billing.StripeService

  @doc """
  Creates a Stripe Checkout session and redirects to Stripe.
  """
  def create_checkout_session(conn, %{"plan" => plan_name}) do
    user = conn.assigns.current_user
    current_plan = Accounts.get_user_plan(user)

    if current_plan.name == plan_name do
      conn
      |> put_flash(:info, "You already have a #{plan_name} subscription!")
      |> redirect(to: ~p"/users/settings")
    else
      success_url = url(~p"/billing/success?session_id={CHECKOUT_SESSION_ID}")
      cancel_url = url(~p"/users/settings")

      with {:ok, customer_id} <- get_or_create_stripe_customer(user),
           plan <- Accounts.get_plan_by_name(plan_name),
           {:ok, price_id} <- validate_plan_price_id(plan, plan_name),
           {:ok, session} <-
             create_stripe_checkout(customer_id, price_id, success_url, cancel_url) do
        conn
        |> put_flash(:info, "Redirecting to secure checkout...")
        |> redirect(external: session.url)
      else
        {:error, :no_price_id} ->
          conn
          |> put_flash(:error, "This plan is not available for purchase.")
          |> redirect(to: ~p"/users/settings")

        {:error, _reason} ->
          conn
          |> put_flash(:error, "Unable to start checkout. Please try again or contact support.")
          |> redirect(to: ~p"/users/settings")
      end
    end
  end

  @doc """
  Success page after checkout completion.
  """
  def checkout_success(conn, _params) do
    # Webhook may not have processed yet, so just redirect with success message
    conn
    |> put_flash(:success, "Thank you for subscribing! Your upgrade is being processed.")
    |> redirect(to: ~p"/users/settings")
  end

  @doc """
  Creates a Stripe Customer Portal session and redirects to Stripe.
  """
  def customer_portal(conn, _params) do
    user = conn.assigns.current_user
    subscription = Billing.get_subscription_by_user_id(user.id)

    case subscription do
      %Billing.Subscription{stripe_customer_id: customer_id} ->
        return_url = url(~p"/users/settings")

        case StripeService.create_billing_portal_session(customer_id, return_url) do
          {:ok, session} ->
            redirect(conn, external: session.url)

          {:error, error} ->
            Logger.error("Failed to create portal session: #{inspect(error)}")

            conn
            |> put_flash(:error, "Unable to access portal. Please try again.")
            |> redirect(to: ~p"/users/settings")
        end

      nil ->
        conn
        |> put_flash(:error, "No active subscription found.")
        |> redirect(to: ~p"/users/settings")
    end
  end

  ## Private Functions

  defp validate_plan_price_id(plan, plan_name) do
    if plan.stripe_price_id do
      {:ok, plan.stripe_price_id}
    else
      Logger.error("Plan #{plan_name} has no stripe_price_id configured")
      {:error, :no_price_id}
    end
  end

  defp create_stripe_checkout(customer_id, price_id, success_url, cancel_url) do
    case StripeService.create_checkout_session(customer_id, price_id, success_url, cancel_url) do
      {:ok, session} ->
        {:ok, session}

      {:error, error} ->
        Logger.error("Failed to create checkout session: #{inspect(error)}")
        {:error, :checkout_failed}
    end
  end

  defp get_or_create_stripe_customer(user) do
    case user.stripe_customer_id do
      nil ->
        create_new_stripe_customer(user)

      customer_id ->
        {:ok, customer_id}
    end
  end

  defp create_new_stripe_customer(user) do
    case StripeService.create_customer(user) do
      {:ok, %{id: customer_id}} ->
        case Accounts.set_stripe_customer_id(user, customer_id) do
          {:ok, _user} -> {:ok, customer_id}
          error -> error
        end

      {:error, error} ->
        Logger.error("Failed to create Stripe customer: #{inspect(error)}")
        {:error, error}
    end
  end
end
