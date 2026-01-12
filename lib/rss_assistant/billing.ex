defmodule RssAssistant.Billing do
  @moduledoc """
  Billing context for Stripe subscription management.
  """

  alias RssAssistant.Accounts
  alias RssAssistant.Accounts.{Plan, User}
  alias RssAssistant.Repo

  require Logger

  @doc """
  Creates a Stripe Checkout session for upgrading to Pro.
  Returns `{:ok, checkout_url}` or `{:error, reason}`.
  """
  def create_checkout_session(%User{} = user) do
    pro_plan = Repo.get_by!(Plan, name: "Pro")

    params = %{
      mode: :subscription,
      client_reference_id: to_string(user.id),
      line_items: [%{price: pro_plan.stripe_price_id, quantity: 1}],
      success_url: success_url() <> "?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: cancel_url()
    }

    params =
      if user.stripe_customer_id do
        Map.put(params, :customer, user.stripe_customer_id)
      else
        Map.put(params, :customer_email, user.email)
      end

    case Stripe.Checkout.Session.create(params) do
      {:ok, %Stripe.Checkout.Session{url: url}} ->
        {:ok, url}

      {:error, %Stripe.Error{} = error} ->
        Logger.error("Stripe checkout error: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Creates a Stripe Customer Portal session.
  Returns `{:ok, portal_url}` or `{:error, reason}`.
  """
  def create_portal_session(%User{stripe_customer_id: nil}), do: {:error, :no_customer}

  def create_portal_session(%User{stripe_customer_id: customer_id}) do
    case Stripe.BillingPortal.Session.create(%{
           customer: customer_id,
           return_url: return_url()
         }) do
      {:ok, %Stripe.BillingPortal.Session{url: url}} ->
        {:ok, url}

      {:error, %Stripe.Error{} = error} ->
        Logger.error("Stripe portal error: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Fulfills a checkout session by retrieving it from Stripe and upgrading the user.
  Called from the success page to ensure upgrade happens even if webhook fails.
  """
  def fulfill_checkout(session_id, %User{} = user) do
    case Stripe.Checkout.Session.retrieve(session_id) do
      {:ok, %Stripe.Checkout.Session{payment_status: "paid"} = session} ->
        if session.client_reference_id == to_string(user.id) do
          handle_checkout_completed(session)
        else
          {:error, :session_mismatch}
        end

      {:ok, %Stripe.Checkout.Session{payment_status: status}} ->
        {:error, "payment not complete: #{status}"}

      {:error, %Stripe.Error{message: message}} ->
        {:error, message}
    end
  end

  @doc """
  Handles checkout.session.completed webhook event.
  Upgrades user to Pro and stores Stripe customer/subscription IDs.
  Idempotent - safe to call multiple times.
  """
  def handle_checkout_completed(%Stripe.Checkout.Session{
        client_reference_id: user_id,
        customer: customer_id,
        subscription: subscription_id
      }) do
    with user when not is_nil(user) <- Repo.get(User, user_id),
         pro_plan <- Repo.get_by!(Plan, name: "Pro"),
         {:ok, user} <-
           update_user_stripe_info(user, %{
             stripe_customer_id: customer_id,
             stripe_subscription_id: subscription_id,
             stripe_subscription_status: "active"
           }),
         {:ok, _user} <- Accounts.change_user_plan(user, pro_plan.id) do
      Logger.info("User #{user_id} upgraded to Pro via Stripe")
      {:ok, :upgraded}
    else
      nil ->
        Logger.error("Checkout completed but user not found: #{user_id}")
        {:error, :user_not_found}

      {:error, reason} ->
        Logger.error("Failed to upgrade user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Handles customer.subscription.updated webhook event.
  Updates the subscription status.
  """
  def handle_subscription_updated(%Stripe.Subscription{id: subscription_id, status: status}) do
    case Repo.get_by(User, stripe_subscription_id: subscription_id) do
      nil ->
        Logger.warning("Subscription updated but user not found: #{subscription_id}")
        {:ok, :user_not_found}

      user ->
        {:ok, _user} = update_user_stripe_info(user, %{stripe_subscription_status: to_string(status)})
        Logger.info("User #{user.id} subscription status updated to #{status}")
        {:ok, :updated}
    end
  end

  @doc """
  Handles customer.subscription.deleted webhook event.
  Downgrades user to Free plan.
  """
  def handle_subscription_deleted(%Stripe.Subscription{id: subscription_id}) do
    case Repo.get_by(User, stripe_subscription_id: subscription_id) do
      nil ->
        Logger.warning("Subscription deleted but user not found: #{subscription_id}")
        {:ok, :user_not_found}

      user ->
        downgrade_to_free(user)
    end
  end

  defp downgrade_to_free(user) do
    free_plan = Repo.get_by!(Plan, name: "Free")

    with {:ok, user} <-
           update_user_stripe_info(user, %{
             stripe_subscription_id: nil,
             stripe_subscription_status: nil
           }),
         {:ok, _user} <- Accounts.change_user_plan(user, free_plan.id) do
      Logger.info("User #{user.id} downgraded to Free")
      {:ok, :downgraded}
    end
  end

  defp update_user_stripe_info(user, attrs) do
    user
    |> User.stripe_changeset(attrs)
    |> Repo.update()
  end

  defp success_url do
    RssAssistantWeb.Endpoint.url() <> "/billing/success"
  end

  defp cancel_url do
    RssAssistantWeb.Endpoint.url() <> "/billing/cancel"
  end

  defp return_url do
    RssAssistantWeb.Endpoint.url() <> "/"
  end
end
