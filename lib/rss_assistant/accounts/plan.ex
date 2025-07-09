defmodule RssAssistant.Accounts.Plan do
  @moduledoc """
  Plan schema for subscription plans.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "plans" do
    field :name, :string
    field :max_feeds, :integer
    field :price, :decimal

    has_many :users, RssAssistant.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(plan, attrs) do
    plan
    |> cast(attrs, [:name, :max_feeds, :price])
    |> validate_required([:name, :max_feeds, :price])
  end
end
