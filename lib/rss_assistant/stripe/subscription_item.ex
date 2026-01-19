defmodule RssAssistant.Stripe.SubscriptionItem do
  @moduledoc """
  Stripe SubscriptionItem struct based on the official Stripe OpenAPI spec.

  IMPORTANT: Per the Stripe API, `current_period_start` and `current_period_end`
  are on the SubscriptionItem, NOT on the Subscription. This is where the billing
  period information actually lives.
  """

  alias RssAssistant.Stripe.Price

  @enforce_keys [:id, :current_period_start, :current_period_end, :price]
  defstruct [
    :id,
    :current_period_start,
    :current_period_end,
    :price,
    :quantity,
    :subscription,
    :metadata,
    :created
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          current_period_start: integer(),
          current_period_end: integer(),
          price: RssAssistant.Stripe.Price.t(),
          quantity: integer() | nil,
          subscription: String.t() | nil,
          metadata: map() | nil,
          created: integer() | nil
        }

  @doc """
  Parses a SubscriptionItem from a Stripe API response map.
  """
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      current_period_start: map["current_period_start"],
      current_period_end: map["current_period_end"],
      price: Price.from_map(map["price"]),
      quantity: map["quantity"],
      subscription: map["subscription"],
      metadata: map["metadata"],
      created: map["created"]
    }
  end
end
