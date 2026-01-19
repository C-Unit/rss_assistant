defmodule RssAssistant.Stripe.CheckoutSession do
  @moduledoc """
  Stripe Checkout Session struct.
  """

  @enforce_keys [:id]
  defstruct [:id, :url, :customer, :mode, :status]

  @type t :: %__MODULE__{
          id: String.t(),
          url: String.t() | nil,
          customer: String.t() | nil,
          mode: String.t() | nil,
          status: String.t() | nil
        }

  @doc """
  Parses a CheckoutSession from a Stripe API response map.
  """
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      url: map["url"],
      customer: map["customer"],
      mode: map["mode"],
      status: map["status"]
    }
  end
end
