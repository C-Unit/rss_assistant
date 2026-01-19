defmodule RssAssistantWeb.StripeHandler do
  @moduledoc """
  Handles Stripe webhook events.
  """
  require Logger

  alias RssAssistant.Billing
  alias RssAssistant.Stripe.Event

  def handle_event(%Event{} = event) do
    Logger.info("Stripe webhook received: #{event.type}")
    Billing.handle_stripe_event(event)
    :ok
  end
end
