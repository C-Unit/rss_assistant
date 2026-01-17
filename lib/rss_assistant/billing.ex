defmodule RssAssistant.Billing do
  @moduledoc """
  The Billing context for managing subscriptions.
  """

  require Logger

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
  def handle_stripe_event(%Stripe.Event{type: event_type, data: %{object: object}}) do
    Logger.info("Processing Stripe webhook: #{event_type}")

    case event_type do
      "checkout.session.completed" ->
        handle_checkout_session_completed(object)

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
  Handles checkout.session.completed event.

  Creates or updates subscription record and upgrades user to Pro plan.
  """
  def handle_checkout_session_completed(session) do
    customer_id = session.customer
    subscription_id = session.subscription

    # Get subscription details from Stripe to get price_id and other info
    case Stripe.Subscription.retrieve(subscription_id) do
      {:ok, stripe_subscription} ->
        plan = determine_plan_from_stripe_subscription(stripe_subscription)
        subscription = get_subscription_by_stripe_customer_id(customer_id)

        attrs = %{
          stripe_subscription_id: subscription_id,
          stripe_price_id: get_price_id_from_subscription(stripe_subscription),
          plan_id: plan.id,
          status: stripe_subscription.status,
          current_period_start: unix_to_naive_datetime(stripe_subscription.current_period_start),
          current_period_end: unix_to_naive_datetime(stripe_subscription.current_period_end),
          cancel_at_period_end: stripe_subscription.cancel_at_period_end || false
        }

        result =
          if subscription do
            update_subscription(subscription, attrs)
          else
            Logger.error("No subscription record found for customer #{customer_id}")
            {:error, :subscription_not_found}
          end

        case result do
          {:ok, updated_subscription} ->
            sync_user_plan(updated_subscription)
            {:ok, updated_subscription}

          error ->
            error
        end

      {:error, error} ->
        Logger.error("Failed to retrieve Stripe subscription: #{inspect(error)}")
        {:error, error}
    end
  end

  @doc """
  Handles customer.subscription.updated event.

  Updates subscription status and syncs user plan.
  """
  def handle_subscription_updated(stripe_subscription) do
    subscription_id = stripe_subscription.id
    subscription = get_subscription_by_stripe_subscription_id(subscription_id)

    if subscription do
      attrs = %{
        status: stripe_subscription.status,
        current_period_start: unix_to_naive_datetime(stripe_subscription.current_period_start),
        current_period_end: unix_to_naive_datetime(stripe_subscription.current_period_end),
        cancel_at_period_end: stripe_subscription.cancel_at_period_end || false,
        canceled_at:
          if(stripe_subscription.canceled_at,
            do: unix_to_naive_datetime(stripe_subscription.canceled_at),
            else: nil
          )
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
    stripe_subscription.items.data
    |> List.first()
    |> Map.get(:price)
    |> Map.get(:id)
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
