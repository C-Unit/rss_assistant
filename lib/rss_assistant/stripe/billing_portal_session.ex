defmodule RssAssistant.Stripe.BillingPortalSession do
  @moduledoc """
  Stripe Billing Portal Session struct.
  """

  @enforce_keys [:id, :url]
  defstruct [:id, :url, :customer, :return_url]

  @type t :: %__MODULE__{
          id: String.t(),
          url: String.t(),
          customer: String.t() | nil,
          return_url: String.t() | nil
        }

  @doc """
  Parses a BillingPortalSession from a Stripe API response map.
  """
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      url: map["url"],
      customer: map["customer"],
      return_url: map["return_url"]
    }
  end
end
