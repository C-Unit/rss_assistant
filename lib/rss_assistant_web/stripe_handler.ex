defmodule RssAssistantWeb.StripeHandler do
  @moduledoc """
  Handles Stripe webhook events.
  """
  @behaviour Stripe.WebhookHandler
  require Logger

  alias RssAssistant.Billing

  @impl true
  def handle_event(%Stripe.Event{} = event) do
    Logger.info("Stripe webhook received: #{event.type}")
    Billing.handle_stripe_event(event)
    :ok
  end
end
