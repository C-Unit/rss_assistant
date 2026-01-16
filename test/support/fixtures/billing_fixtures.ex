defmodule RssAssistant.BillingFixtures do
  @moduledoc """
  Test fixtures for Stripe billing structs.
  """

  def checkout_session_fixture(attrs \\ %{}) do
    defaults = %{
      id: "cs_test_#{System.unique_integer([:positive])}",
      client_reference_id: "1",
      customer: "cus_test_#{System.unique_integer([:positive])}",
      subscription: "sub_test_#{System.unique_integer([:positive])}",
      payment_status: "paid",
      status: "complete",
      mode: "subscription",
      success_url: "http://localhost:4000/billing/success",
      cancel_url: "http://localhost:4000/billing/cancel",
      customer_email: "test@example.com",
      url: nil,
      amount_total: 9999,
      currency: "usd"
    }

    struct(Stripe.Checkout.Session, Map.merge(defaults, attrs))
  end

  def subscription_fixture(attrs \\ %{}) do
    defaults = %{
      id: "sub_test_#{System.unique_integer([:positive])}",
      customer: "cus_test_#{System.unique_integer([:positive])}",
      status: "active",
      cancel_at_period_end: false,
      current_period_start: DateTime.utc_now() |> DateTime.to_unix(),
      current_period_end: DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.to_unix()
    }

    struct(Stripe.Subscription, Map.merge(defaults, attrs))
  end

  def portal_session_fixture(attrs \\ %{}) do
    defaults = %{
      id: "bps_test_#{System.unique_integer([:positive])}",
      url: "https://billing.stripe.com/session/test_portal",
      return_url: "http://localhost:4000/"
    }

    struct(Stripe.BillingPortal.Session, Map.merge(defaults, attrs))
  end
end
