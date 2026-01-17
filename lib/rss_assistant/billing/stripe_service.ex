defmodule RssAssistant.Billing.StripeService do
  @moduledoc """
  Wrapper around the Stripe API via the stripity_stripe library.

  This module is the ONLY place that directly uses the Stripe library.
  """

  @doc """
  Creates a Stripe customer with the given user's email and metadata.
  """
  def create_customer(user) do
    Stripe.Customer.create(%{
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
    Stripe.Checkout.Session.create(%{
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
    Stripe.BillingPortal.Session.create(%{
      customer: customer_id,
      return_url: return_url
    })
  end

  @doc """
  Constructs and verifies a Stripe webhook event from the raw payload and signature.

  Returns {:ok, event} or {:error, error}
  """
  def construct_webhook_event(payload, signature) do
    webhook_secret = Application.get_env(:rss_assistant, :stripe_webhook_secret)

    Stripe.Webhook.construct_event(payload, signature, webhook_secret)
  end

  @doc """
  Cancels a Stripe subscription.

  Returns {:ok, subscription} or {:error, error}
  """
  def cancel_subscription(subscription_id) do
    Stripe.Subscription.cancel(subscription_id, %{})
  end

  @doc """
  Reactivates a canceled Stripe subscription (removes cancel_at_period_end).

  Returns {:ok, subscription} or {:error, error}
  """
  def reactivate_subscription(subscription_id) do
    Stripe.Subscription.update(subscription_id, %{
      cancel_at_period_end: false
    })
  end
end
