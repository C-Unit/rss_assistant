defmodule RssAssistant.Billing.StripeWebhookHandler do
  @moduledoc """
  Handles Stripe webhook events.
  Implements the `Stripe.WebhookHandler` behaviour.
  """

  @behaviour Stripe.WebhookHandler

  alias RssAssistant.Billing

  require Logger

  @impl true
  def handle_event(%Stripe.Event{type: "checkout.session.completed", data: %{object: session}}) do
    Logger.info("Processing checkout.session.completed webhook")

    case Billing.handle_checkout_completed(session) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def handle_event(%Stripe.Event{
        type: "customer.subscription.updated",
        data: %{object: subscription}
      }) do
    Logger.info("Processing customer.subscription.updated webhook")
    {:ok, _} = Billing.handle_subscription_updated(subscription)
    :ok
  end

  @impl true
  def handle_event(%Stripe.Event{
        type: "customer.subscription.deleted",
        data: %{object: subscription}
      }) do
    Logger.info("Processing customer.subscription.deleted webhook")
    {:ok, _} = Billing.handle_subscription_deleted(subscription)
    :ok
  end

  @impl true
  def handle_event(%Stripe.Event{type: "invoice.payment_failed", data: %{object: invoice}}) do
    Logger.warning("Payment failed for customer: #{invoice["customer"]}")
    :ok
  end

  @impl true
  def handle_event(%Stripe.Event{type: type}) do
    Logger.debug("Ignoring Stripe event: #{type}")
    :ok
  end
end
