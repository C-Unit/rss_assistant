defmodule RssAssistant.Stripe.Customer do
  @moduledoc """
  Stripe Customer struct.
  """

  @enforce_keys [:id]
  defstruct [:id, :email, :metadata, :created]

  @type t :: %__MODULE__{
          id: String.t(),
          email: String.t() | nil,
          metadata: map() | nil,
          created: integer() | nil
        }

  @doc """
  Parses a Customer from a Stripe API response map.
  """
  def from_map(map) when is_map(map) do
    %__MODULE__{
      id: map["id"],
      email: map["email"],
      metadata: map["metadata"],
      created: map["created"]
    }
  end
end
