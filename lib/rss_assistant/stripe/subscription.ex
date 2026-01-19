defmodule RssAssistant.Stripe.Subscription do
  @moduledoc """
  Stripe Subscription struct based on the official Stripe OpenAPI spec.

  Note: In the Stripe API, `current_period_start` and `current_period_end`
  are on the SubscriptionItem, NOT on the Subscription itself.
  """

  alias RssAssistant.Stripe.SubscriptionItem

  @enforce_keys [:id, :customer, :status]
  defstruct [
    :id,
    :customer,
    :status,
    :items,
    :cancel_at_period_end,
    :canceled_at,
    :ended_at,
    :billing_cycle_anchor,
    :created,
    :metadata
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          customer: String.t(),
          status: String.t(),
          items: %{data: [RssAssistant.Stripe.SubscriptionItem.t()]} | nil,
          cancel_at_period_end: boolean() | nil,
          canceled_at: integer() | nil,
          ended_at: integer() | nil,
          billing_cycle_anchor: integer() | nil,
          created: integer() | nil,
          metadata: map() | nil
        }

  @doc """
  Parses a Subscription from a Stripe API response map.
  """
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      customer: map["customer"],
      status: map["status"],
      items: parse_items(map["items"]),
      cancel_at_period_end: map["cancel_at_period_end"],
      canceled_at: map["canceled_at"],
      ended_at: map["ended_at"],
      billing_cycle_anchor: map["billing_cycle_anchor"],
      created: map["created"],
      metadata: map["metadata"]
    }
  end

  defp parse_items(%{"data" => data}) when is_list(data) do
    %{data: Enum.map(data, &SubscriptionItem.from_map/1)}
  end
end
