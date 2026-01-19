defmodule RssAssistant.Stripe.Event do
  @moduledoc """
  Stripe Event struct for webhook payloads.
  """

  alias RssAssistant.Stripe.Invoice
  alias RssAssistant.Stripe.Subscription

  @enforce_keys [:id, :type, :data]
  defstruct [:id, :type, :data, :created, :api_version]

  @type t :: %__MODULE__{
          id: String.t(),
          type: String.t(),
          data: %{object: map()},
          created: integer() | nil,
          api_version: String.t() | nil
        }

  @doc """
  Parses an Event from a Stripe webhook payload.
  """
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      type: map["type"],
      data: parse_data(map["data"]),
      created: map["created"],
      api_version: map["api_version"]
    }
  end

  defp parse_data(%{"object" => object}) when is_map(object) do
    %{object: parse_event_object(object)}
  end

  defp parse_data(_), do: %{object: %{}}

  defp parse_event_object(%{"object" => "subscription"} = map) do
    Subscription.from_map(map)
  end

  defp parse_event_object(%{"object" => "invoice"} = map) do
    Invoice.from_map(map)
  end

  defp parse_event_object(map), do: map
end
