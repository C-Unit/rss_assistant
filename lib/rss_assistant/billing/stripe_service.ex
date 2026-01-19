defmodule RssAssistant.Billing.StripeService do
  @moduledoc """
  Wrapper around the Stripe API via our custom Req-based client.

  This module is the ONLY place that directly uses the Stripe client.
  """

  alias RssAssistant.Stripe

  @doc """
  Creates a Stripe customer with the given user's email and metadata.
  """
  def create_customer(user) do
    Stripe.create_customer(%{
      email: user.email,
      metadata: %{
        user_id: user.id
      }
    })
  end

  @doc """
  Creates a Stripe Checkout Session for subscription.

  Returns {:ok, session} or {:error, error}
  """
  def create_checkout_session(customer_id, price_id, success_url, cancel_url) do
    Stripe.create_checkout_session(%{
      customer: customer_id,
      mode: "subscription",
      line_items: [
        %{
          price: price_id,
          quantity: 1
        }
      ],
      success_url: success_url,
      cancel_url: cancel_url
    })
  end

  @doc """
  Creates a Stripe Billing Portal Session for subscription management.

  Returns {:ok, session} or {:error, error}
  """
  def create_billing_portal_session(customer_id, return_url) do
    Stripe.create_billing_portal_session(%{
      customer: customer_id,
      return_url: return_url
    })
  end

  @doc """
  Cancels a Stripe subscription.

  Returns {:ok, subscription} or {:error, error}
  """
  def cancel_subscription(subscription_id) do
    Stripe.cancel_subscription(subscription_id)
  end

  @doc """
  Reactivates a canceled Stripe subscription (removes cancel_at_period_end).

  Returns {:ok, subscription} or {:error, error}
  """
  def reactivate_subscription(subscription_id) do
    Stripe.update_subscription(subscription_id, %{
      cancel_at_period_end: false
    })
  end
end
