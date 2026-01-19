defmodule RssAssistant.Stripe do
  @moduledoc """
  Req-based Stripe API client.

  This module provides a thin wrapper around the Stripe API using Req.
  It replaces the stripity_stripe library to give us full control over
  struct definitions and avoid bugs with missing/incorrect fields.

  ## Why we built this

  The stripity_stripe library (v3.2.0) has bugs where struct fields don't match
  the actual Stripe API:

  - `Stripe.Subscription` struct has `current_period_start/end` fields that
    DON'T EXIST on the subscription object in the API
  - `Stripe.SubscriptionItem` struct is MISSING `current_period_start/end` fields
    that ARE on the subscription_item object in the API
  - Fields not defined in structs get silently dropped during JSON parsing

  ## How this was generated

  Structs were built by consulting the official Stripe OpenAPI specification:

  - Spec repo: https://github.com/stripe/openapi
  - Raw spec: https://raw.githubusercontent.com/stripe/openapi/master/openapi/spec3.json

  To find the correct fields for subscription_item, we parsed the spec with jq:

      curl -s https://raw.githubusercontent.com/stripe/openapi/master/openapi/spec3.json | \\
        jq '.components.schemas.subscription_item.properties | keys'

  This revealed `current_period_start` and `current_period_end` are on SubscriptionItem,
  not Subscription.

  ## Official test fixture (from Stripe OpenAPI spec)

      {
        "id": "si_QXhVBoJ7NQdNXh",
        "object": "subscription_item",
        "current_period_end": 976287773,
        "current_period_start": 1896570518,
        "price": {
          "id": "price_1PgafmB7WZ01zgkW6dKueIc5",
          "currency": "usd",
          "unit_amount": 2000
        },
        "quantity": 1,
        "subscription": "sub_1Pgc6xB7WZ01zgkWJMvZp5ja"
      }

  ## References

  - Stripe OpenAPI spec: https://github.com/stripe/openapi
  - Dashbit blog on building SDKs with Req: https://dashbit.co/blog/sdks-with-req-stripe
  """

  alias RssAssistant.Stripe.BillingPortalSession
  alias RssAssistant.Stripe.CheckoutSession
  alias RssAssistant.Stripe.Customer
  alias RssAssistant.Stripe.Subscription

  require Logger

  @api_version "2025-01-27.acacia"
  @base_url "https://api.stripe.com/v1"

  @doc """
  Builds a configured Req client for Stripe API calls.
  """
  def client(opts \\ []) do
    api_key = Keyword.get(opts, :api_key, api_key())

    Req.new(
      base_url: @base_url,
      headers: [
        {"authorization", "Bearer #{api_key}"},
        {"stripe-version", @api_version},
        {"content-type", "application/x-www-form-urlencoded"}
      ]
    )
  end

  @doc """
  Creates a Stripe customer.

  ## Options
    * `:email` - Customer email address
    * `:metadata` - Map of metadata key-value pairs
  """
  def create_customer(params, opts \\ []) do
    client(opts)
    |> Req.post(url: "/customers", form: encode_params(params))
    |> handle_response(&Customer.from_map/1)
  end

  @doc """
  Creates a Stripe Checkout Session for subscription.

  ## Options
    * `:customer` - Stripe customer ID
    * `:mode` - Session mode (e.g., "subscription")
    * `:line_items` - List of line items
    * `:success_url` - URL to redirect on success
    * `:cancel_url` - URL to redirect on cancel
  """
  def create_checkout_session(params, opts \\ []) do
    client(opts)
    |> Req.post(url: "/checkout/sessions", form: encode_params(params))
    |> handle_response(&CheckoutSession.from_map/1)
  end

  @doc """
  Creates a Stripe Billing Portal Session.

  ## Options
    * `:customer` - Stripe customer ID
    * `:return_url` - URL to redirect after portal
  """
  def create_billing_portal_session(params, opts \\ []) do
    client(opts)
    |> Req.post(url: "/billing_portal/sessions", form: encode_params(params))
    |> handle_response(&BillingPortalSession.from_map/1)
  end

  @doc """
  Updates a Stripe subscription.

  ## Options
    * `:cancel_at_period_end` - Whether to cancel at period end
  """
  def update_subscription(subscription_id, params, opts \\ []) do
    client(opts)
    |> Req.post(url: "/subscriptions/#{subscription_id}", form: encode_params(params))
    |> handle_response(&Subscription.from_map/1)
  end

  @doc """
  Cancels a Stripe subscription immediately.
  """
  def cancel_subscription(subscription_id, opts \\ []) do
    client(opts)
    |> Req.delete(url: "/subscriptions/#{subscription_id}")
    |> handle_response(&Subscription.from_map/1)
  end

  defp api_key do
    Application.get_env(:rss_assistant, :stripe_api_key) ||
      raise "Stripe API key not configured. Set :stripe_api_key in :rss_assistant config."
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}, parser)
       when status in 200..299 do
    {:ok, parser.(body)}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}, _parser) do
    error = get_in(body, ["error", "message"]) || "Unknown Stripe error"
    Logger.error("Stripe API error (#{status}): #{error}")
    {:error, %{status: status, message: error, body: body}}
  end

  defp handle_response({:error, reason}, _parser) do
    Logger.error("Stripe request failed: #{inspect(reason)}")
    {:error, reason}
  end

  @doc """
  Encodes parameters for form-urlencoded requests.

  Handles nested maps and lists as Stripe expects them.
  """
  def encode_params(params) when is_map(params) do
    params
    |> Enum.flat_map(&encode_param/1)
    |> Enum.into(%{})
  end

  defp encode_param({key, value}) when is_map(value) do
    Enum.flat_map(value, fn {k, v} ->
      encode_param({"#{key}[#{k}]", v})
    end)
  end

  defp encode_param({key, value}) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(&encode_list_item(key, &1))
  end

  defp encode_param({key, value}) when is_boolean(value) do
    [{to_string(key), to_string(value)}]
  end

  defp encode_param({key, value}) do
    [{to_string(key), to_string(value)}]
  end

  defp encode_list_item(key, {item, index}) when is_map(item) do
    Enum.flat_map(item, fn {k, v} ->
      encode_param({"#{key}[#{index}][#{k}]", v})
    end)
  end

  defp encode_list_item(key, {item, index}) do
    [{"#{key}[#{index}]", to_string(item)}]
  end
end
