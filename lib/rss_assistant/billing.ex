defmodule RssAssistant.Billing do
  @moduledoc """
  The Billing context for managing subscriptions.
  """

  require Logger

  import Ecto.Query

  alias RssAssistant.Accounts
  alias RssAssistant.Billing.Subscription
  alias RssAssistant.Repo

  ## Query Functions

  @doc """
  Gets a subscription by user ID.
  """
  def get_subscription_by_user_id(user_id) do
    Repo.get_by(Subscription, user_id: user_id)
  end

  @doc """
  Gets a subscription by Stripe customer ID.
  """
  def get_subscription_by_stripe_customer_id(customer_id) do
    Repo.get_by(Subscription, stripe_customer_id: customer_id)
  end

  @doc """
  Gets a subscription by Stripe subscription ID.
  """
  def get_subscription_by_stripe_subscription_id(subscription_id) do
    Repo.get_by(Subscription, stripe_subscription_id: subscription_id)
  end

  ## CRUD Operations

  @doc """
  Creates a subscription.
  """
  def create_subscription(attrs \\ %{}) do
    %Subscription{}
    |> Subscription.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a subscription.
  """
  def update_subscription(%Subscription{} = subscription, attrs) do
    subscription
    |> Subscription.changeset(attrs)
    |> Repo.update()
  end

  ## Business Logic

  @doc """
  Syncs a user's plan based on their subscription status.

  If subscription is active, upgrades to subscription plan.
  If subscription is inactive, downgrades to Free plan.
  """
  def sync_user_plan(%Subscription{} = subscription) do
    subscription = Repo.preload(subscription, [:user, :plan])

    target_plan =
      if Subscription.active?(subscription) do
        subscription.plan
      else
        Accounts.get_plan_by_name("Free")
      end

    if subscription.user.plan_id != target_plan.id do
      Logger.info(
        "Syncing user #{subscription.user_id} from plan #{subscription.user.plan_id} to #{target_plan.id}"
      )

      Accounts.change_user_plan(subscription.user, target_plan.id)
    else
      {:ok, subscription.user}
    end
  end

  ## Webhook Handlers

  @doc """
  Handles a Stripe webhook event by dispatching to specific handlers.
  """
  def handle_stripe_event(%RssAssistant.Stripe.Event{type: event_type, data: %{object: object}}) do
    Logger.info("Processing Stripe webhook: #{event_type}")

    case event_type do
      "customer.subscription.created" ->
        # Ignore - subscription.updated also fires and handles creation via upsert
        {:ok, :ignored}

      "customer.subscription.updated" ->
        handle_subscription_updated(object)

      "customer.subscription.deleted" ->
        handle_subscription_deleted(object)

      "invoice.payment_failed" ->
        handle_invoice_payment_failed(object)

      _ ->
        Logger.info("Ignoring unhandled Stripe event: #{event_type}")
        {:ok, :ignored}
    end
  rescue
    error ->
      Logger.error("Error processing Stripe webhook: #{inspect(error)}")
      {:error, error}
  end

  def handle_stripe_event(_event) do
    {:ok, :ignored}
  end

  @doc """
  Handles customer.subscription.created event.
  """
  def handle_subscription_created(stripe_subscription) do
    upsert_subscription_from_stripe(stripe_subscription)
  end

  @doc """
  Handles customer.subscription.updated event.
  """
  def handle_subscription_updated(stripe_subscription) do
    upsert_subscription_from_stripe(stripe_subscription)
  end

  @doc """
  Upserts a subscription from a Stripe subscription object.

  This is idempotent - it will create the subscription if it doesn't exist,
  or update it if it does. Uses SELECT FOR UPDATE to prevent race conditions
  between parallel webhook events.
  """
  def upsert_subscription_from_stripe(stripe_subscription) do
    Repo.transact(fn -> do_upsert_subscription(stripe_subscription) end)
  end

  defp do_upsert_subscription(stripe_subscription) do
    customer_id = stripe_subscription.customer

    with {:ok, user} <- find_user_by_customer_id(customer_id),
         subscription <- get_subscription_for_update(user.id),
         attrs <- build_subscription_attrs(stripe_subscription, user, customer_id),
         {:ok, sub} <- upsert_subscription(subscription, attrs) do
      sync_user_plan(sub)
      {:ok, sub}
    end
  end

  defp find_user_by_customer_id(customer_id) do
    case Accounts.get_user_by_stripe_customer_id(customer_id) do
      %Accounts.User{} = user ->
        {:ok, user}

      nil ->
        Logger.warning("User not found for Stripe customer ID: #{customer_id}")
        {:error, :user_not_found}
    end
  end

  defp get_subscription_for_update(user_id) do
    Subscription
    |> where(user_id: ^user_id)
    |> lock("FOR UPDATE")
    |> Repo.one()
  end

  defp build_subscription_attrs(stripe_subscription, user, customer_id) do
    plan = determine_plan_from_stripe_subscription(stripe_subscription)
    [item | _] = stripe_subscription.items.data

    %{
      user_id: user.id,
      plan_id: plan.id,
      stripe_customer_id: customer_id,
      stripe_subscription_id: stripe_subscription.id,
      stripe_price_id: get_price_id_from_subscription(stripe_subscription),
      status: stripe_subscription.status,
      current_period_start: unix_to_naive_datetime(item.current_period_start),
      current_period_end: unix_to_naive_datetime(item.current_period_end),
      cancel_at_period_end: stripe_subscription.cancel_at_period_end || false,
      canceled_at:
        if(stripe_subscription.canceled_at,
          do: unix_to_naive_datetime(stripe_subscription.canceled_at),
          else: nil
        )
    }
  end

  defp upsert_subscription(nil, attrs), do: create_subscription(attrs)
  defp upsert_subscription(subscription, attrs), do: update_subscription(subscription, attrs)

  @doc """
  Handles customer.subscription.deleted event.

  Marks subscription as canceled and downgrades user to Free plan.
  """
  def handle_subscription_deleted(stripe_subscription) do
    subscription_id = stripe_subscription.id
    subscription = get_subscription_by_stripe_subscription_id(subscription_id)

    if subscription do
      attrs = %{
        status: "canceled",
        canceled_at:
          unix_to_naive_datetime(stripe_subscription.canceled_at || stripe_subscription.ended_at)
      }

      case update_subscription(subscription, attrs) do
        {:ok, updated_subscription} ->
          sync_user_plan(updated_subscription)
          {:ok, updated_subscription}

        error ->
          error
      end
    else
      Logger.warning("Subscription not found for Stripe subscription ID: #{subscription_id}")
      {:error, :not_found}
    end
  end

  @doc """
  Handles invoice.payment_failed event.

  Updates subscription status and syncs user plan (may downgrade to Free).
  """
  def handle_invoice_payment_failed(invoice) do
    subscription_id = invoice.subscription

    if subscription_id do
      subscription = get_subscription_by_stripe_subscription_id(subscription_id)

      if subscription do
        # Update status to past_due (Stripe will have already updated the subscription)
        # We'll let the subscription.updated event handle the full sync
        Logger.warning("Payment failed for subscription #{subscription_id}")
        {:ok, :payment_failed}
      else
        Logger.warning("Subscription not found for invoice: #{subscription_id}")
        {:error, :not_found}
      end
    else
      {:ok, :no_subscription}
    end
  end

  ## Helper Functions

  @doc """
  Converts a Unix timestamp to NaiveDateTime.
  """
  def unix_to_naive_datetime(nil), do: nil

  def unix_to_naive_datetime(timestamp) when is_integer(timestamp) do
    DateTime.from_unix!(timestamp)
    |> DateTime.to_naive()
  end

  @doc """
  Gets the price ID from a Stripe subscription object.
  """
  def get_price_id_from_subscription(stripe_subscription) do
    [item | _] = stripe_subscription.items.data
    item.price.id
  end

  # Determines which plan to assign based on Stripe subscription price_id.
  defp determine_plan_from_stripe_subscription(stripe_subscription) do
    price_id = get_price_id_from_subscription(stripe_subscription)

    # Look up plan by stripe_price_id
    case Repo.get_by(Accounts.Plan, stripe_price_id: price_id) do
      %Accounts.Plan{} = plan ->
        plan

      nil ->
        Logger.warning("No plan found for Stripe price_id: #{price_id}, defaulting to Pro")
        Accounts.get_plan_by_name("Pro")
    end
  end
end
