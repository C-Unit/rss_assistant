defmodule RssAssistant.Stripe.Invoice do
  @moduledoc """
  Stripe Invoice struct for webhook payloads.
  """

  defstruct [:id, :subscription, :customer, :status, :amount_due, :amount_paid]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          subscription: String.t() | nil,
          customer: String.t() | nil,
          status: String.t() | nil,
          amount_due: integer() | nil,
          amount_paid: integer() | nil
        }

  @doc """
  Parses an Invoice from a Stripe API response map.
  """
  def from_map(nil), do: nil

  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      subscription: map["subscription"],
      customer: map["customer"],
      status: map["status"],
      amount_due: map["amount_due"],
      amount_paid: map["amount_paid"]
    }
  end
end
