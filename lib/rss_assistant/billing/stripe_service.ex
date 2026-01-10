defmodule RssAssistant.Billing.StripeService do
  @moduledoc """
  Service module for interacting with the Stripe API.
  """

  alias RssAssistant.Billing
  alias RssAssistant.Billing.Subscription
  alias RssAssistant.Accounts.User

  @doc """
  Creates a Stripe customer for a user.
  """
  def create_customer(%User{} = user) do
    Stripe.Customer.create(%{
      email: user.email,
      metadata: %{
        user_id: user.id
      }
    })
  end

  @doc """
  Creates a Stripe Checkout Session for upgrading to Pro plan.
  """
  def create_checkout_session(%User{} = user, plan_name, success_url, cancel_url) do
    price_id = get_price_id_for_plan(plan_name)

    # Get or create Stripe customer
    {:ok, customer_id} = get_or_create_customer(user)

    Stripe.Session.create(%{
      customer: customer_id,
      mode: "subscription",
      line_items: [
        %{
          price: price_id,
          quantity: 1
        }
      ],
      success_url: success_url,
      cancel_url: cancel_url,
      metadata: %{
        user_id: user.id,
        plan_name: plan_name
      },
      subscription_data: %{
        metadata: %{
          user_id: user.id,
          plan_name: plan_name
        }
      }
    })
  end

  @doc """
  Creates a billing portal session for managing subscriptions.
  """
  def create_billing_portal_session(%User{} = user, return_url) do
    case Billing.get_subscription_by_user_id(user.id) do
      %Subscription{stripe_customer_id: customer_id} ->
        Stripe.BillingPortal.Session.create(%{
          customer: customer_id,
          return_url: return_url
        })

      nil ->
        {:error, :no_subscription}
    end
  end

  @doc """
  Cancels a subscription at the end of the billing period.
  """
  def cancel_subscription(%Subscription{stripe_subscription_id: subscription_id}) do
    Stripe.Subscription.update(subscription_id, %{
      cancel_at_period_end: true
    })
  end

  @doc """
  Reactivates a subscription that was set to cancel.
  """
  def reactivate_subscription(%Subscription{stripe_subscription_id: subscription_id}) do
    Stripe.Subscription.update(subscription_id, %{
      cancel_at_period_end: false
    })
  end

  @doc """
  Gets or creates a Stripe customer for a user.
  Returns {:ok, customer_id}
  """
  def get_or_create_customer(%User{} = user) do
    case Billing.get_subscription_by_user_id(user.id) do
      %Subscription{stripe_customer_id: customer_id} ->
        {:ok, customer_id}

      nil ->
        case create_customer(user) do
          {:ok, %Stripe.Customer{id: customer_id}} ->
            {:ok, customer_id}

          {:error, error} ->
            {:error, error}
        end
    end
  end

  @doc """
  Retrieves the Stripe Price ID for a given plan name.
  """
  defp get_price_id_for_plan("Pro") do
    Application.get_env(:rss_assistant, :stripe_pro_price_id)
  end

  defp get_price_id_for_plan(_plan_name) do
    # Default to Pro price if unknown plan
    Application.get_env(:rss_assistant, :stripe_pro_price_id)
  end

  @doc """
  Constructs a Stripe webhook event from the payload and signature.
  """
  def construct_webhook_event(payload, signature) do
    endpoint_secret = Application.get_env(:rss_assistant, :stripe_webhook_secret)
    Stripe.Webhook.construct_event(payload, signature, endpoint_secret)
  end
end
