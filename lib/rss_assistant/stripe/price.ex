defmodule RssAssistant.Stripe.Price do
  @moduledoc """
  Stripe Price struct based on the official Stripe OpenAPI spec.
  """

  defstruct [:id, :currency, :unit_amount, :recurring, :product]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          currency: String.t() | nil,
          unit_amount: integer() | nil,
          recurring: map() | nil,
          product: String.t() | nil
        }

  @doc """
  Parses a Price from a Stripe API response map.
  """
  def from_map(nil), do: nil

  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      currency: map["currency"],
      unit_amount: map["unit_amount"],
      recurring: map["recurring"],
      product: map["product"]
    }
  end
end
