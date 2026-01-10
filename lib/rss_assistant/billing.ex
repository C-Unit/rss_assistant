defmodule RssAssistant.Billing do
  @moduledoc """
  The Billing context handles subscriptions and Stripe integration.
  """

  import Ecto.Query, warn: false
  alias RssAssistant.Repo
  alias RssAssistant.Billing.Subscription
  alias RssAssistant.Accounts
  alias RssAssistant.Accounts.{User, Plan}

  @doc """
  Gets a subscription by user ID.
  Returns nil if no subscription exists.
  """
  def get_subscription_by_user_id(user_id) do
    Repo.get_by(Subscription, user_id: user_id)
    |> Repo.preload([:user, :plan])
  end

  @doc """
  Gets a subscription by Stripe customer ID.
  """
  def get_subscription_by_stripe_customer_id(stripe_customer_id) do
    Repo.get_by(Subscription, stripe_customer_id: stripe_customer_id)
    |> Repo.preload([:user, :plan])
  end

  @doc """
  Gets a subscription by Stripe subscription ID.
  """
  def get_subscription_by_stripe_subscription_id(stripe_subscription_id) do
    Repo.get_by(Subscription, stripe_subscription_id: stripe_subscription_id)
    |> Repo.preload([:user, :plan])
  end

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

  @doc """
  Deletes a subscription.
  """
  def delete_subscription(%Subscription{} = subscription) do
    Repo.delete(subscription)
  end

  @doc """
  Syncs a user's plan based on their subscription status.
  If subscription is active, ensures user has the correct plan.
  If subscription is not active, downgrades user to Free plan.
  """
  def sync_user_plan(%Subscription{} = subscription) do
    subscription = Repo.preload(subscription, [:user, :plan])

    if Subscription.active?(subscription) do
      # Ensure user has the subscription's plan
      if subscription.user.plan_id != subscription.plan_id do
        Accounts.change_user_plan(subscription.user, subscription.plan_id)
      else
        {:ok, subscription.user}
      end
    else
      # Downgrade to Free plan if subscription is not active
      free_plan = Accounts.get_plan_by_name("Free")

      if subscription.user.plan_id != free_plan.id do
        Accounts.change_user_plan(subscription.user, free_plan.id)
      else
        {:ok, subscription.user}
      end
    end
  end

  @doc """
  Handles Stripe webhook events and updates subscription accordingly.
  """
  def handle_stripe_event(%{"type" => event_type, "data" => %{"object" => object}}) do
    case event_type do
      "customer.subscription.created" -> handle_subscription_created(object)
      "customer.subscription.updated" -> handle_subscription_updated(object)
      "customer.subscription.deleted" -> handle_subscription_deleted(object)
      "invoice.payment_succeeded" -> handle_invoice_payment_succeeded(object)
      "invoice.payment_failed" -> handle_invoice_payment_failed(object)
      _ -> {:ok, :ignored}
    end
  end

  defp handle_subscription_created(stripe_subscription) do
    case get_subscription_by_stripe_subscription_id(stripe_subscription["id"]) do
      nil ->
        # Create new subscription if it doesn't exist
        plan = determine_plan_from_stripe_subscription(stripe_subscription)

        subscription_attrs = %{
          user_id: get_user_id_from_stripe_customer(stripe_subscription["customer"]),
          plan_id: plan.id,
          stripe_customer_id: stripe_subscription["customer"],
          stripe_subscription_id: stripe_subscription["id"],
          stripe_price_id: get_price_id_from_subscription(stripe_subscription),
          status: stripe_subscription["status"],
          current_period_start: unix_to_naive_datetime(stripe_subscription["current_period_start"]),
          current_period_end: unix_to_naive_datetime(stripe_subscription["current_period_end"]),
          cancel_at_period_end: stripe_subscription["cancel_at_period_end"]
        }

        with {:ok, subscription} <- create_subscription(subscription_attrs) do
          sync_user_plan(subscription)
          {:ok, subscription}
        end

      subscription ->
        # Update existing subscription
        handle_subscription_updated(stripe_subscription)
    end
  end

  defp handle_subscription_updated(stripe_subscription) do
    with subscription when not is_nil(subscription) <-
           get_subscription_by_stripe_subscription_id(stripe_subscription["id"]) do
      plan = determine_plan_from_stripe_subscription(stripe_subscription)

      update_attrs = %{
        plan_id: plan.id,
        stripe_price_id: get_price_id_from_subscription(stripe_subscription),
        status: stripe_subscription["status"],
        current_period_start: unix_to_naive_datetime(stripe_subscription["current_period_start"]),
        current_period_end: unix_to_naive_datetime(stripe_subscription["current_period_end"]),
        cancel_at_period_end: stripe_subscription["cancel_at_period_end"],
        canceled_at:
          if(stripe_subscription["canceled_at"],
            do: unix_to_naive_datetime(stripe_subscription["canceled_at"]),
            else: nil
          )
      }

      with {:ok, subscription} <- update_subscription(subscription, update_attrs) do
        sync_user_plan(subscription)
        {:ok, subscription}
      end
    else
      nil -> {:error, :subscription_not_found}
    end
  end

  defp handle_subscription_deleted(stripe_subscription) do
    with subscription when not is_nil(subscription) <-
           get_subscription_by_stripe_subscription_id(stripe_subscription["id"]) do
      update_attrs = %{
        status: "canceled",
        canceled_at: unix_to_naive_datetime(stripe_subscription["canceled_at"] || System.os_time(:second))
      }

      with {:ok, subscription} <- update_subscription(subscription, update_attrs) do
        sync_user_plan(subscription)
        {:ok, subscription}
      end
    else
      nil -> {:error, :subscription_not_found}
    end
  end

  defp handle_invoice_payment_succeeded(_invoice) do
    # Payment succeeded, subscription should be active via subscription.updated event
    {:ok, :handled}
  end

  defp handle_invoice_payment_failed(invoice) do
    # Payment failed, might need to notify user or handle accordingly
    with subscription when not is_nil(subscription) <-
           get_subscription_by_stripe_subscription_id(invoice["subscription"]) do
      # Optionally send notification to user about failed payment
      {:ok, subscription}
    else
      nil -> {:error, :subscription_not_found}
    end
  end

  defp determine_plan_from_stripe_subscription(stripe_subscription) do
    # You'll need to configure price IDs in your environment
    # For now, we'll default to Pro plan for any paid subscription
    price_id = get_price_id_from_subscription(stripe_subscription)
    pro_price_id = Application.get_env(:rss_assistant, :stripe_pro_price_id)

    if price_id == pro_price_id do
      Accounts.get_plan_by_name("Pro")
    else
      # Default to Free if we don't recognize the price
      Accounts.get_plan_by_name("Free")
    end
  end

  defp get_price_id_from_subscription(stripe_subscription) do
    case stripe_subscription["items"]["data"] do
      [%{"price" => %{"id" => price_id}} | _] -> price_id
      _ -> nil
    end
  end

  defp get_user_id_from_stripe_customer(stripe_customer_id) do
    # Assuming subscription already has the user_id
    # This function is a placeholder - in practice, you'd look up by customer_id
    case get_subscription_by_stripe_customer_id(stripe_customer_id) do
      %Subscription{user_id: user_id} -> user_id
      nil -> nil
    end
  end

  defp unix_to_naive_datetime(nil), do: nil

  defp unix_to_naive_datetime(unix_timestamp) when is_integer(unix_timestamp) do
    DateTime.from_unix!(unix_timestamp)
    |> DateTime.to_naive_datetime()
  end

  defp unix_to_naive_datetime(_), do: nil
end
