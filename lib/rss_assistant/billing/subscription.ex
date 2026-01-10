defmodule RssAssistant.Billing.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  schema "subscriptions" do
    field :stripe_customer_id, :string
    field :stripe_subscription_id, :string
    field :stripe_price_id, :string
    field :status, :string
    field :current_period_start, :naive_datetime
    field :current_period_end, :naive_datetime
    field :cancel_at_period_end, :boolean, default: false
    field :canceled_at, :naive_datetime

    belongs_to :user, RssAssistant.Accounts.User
    belongs_to :plan, RssAssistant.Accounts.Plan

    timestamps()
  end

  @doc false
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :user_id,
      :plan_id,
      :stripe_customer_id,
      :stripe_subscription_id,
      :stripe_price_id,
      :status,
      :current_period_start,
      :current_period_end,
      :cancel_at_period_end,
      :canceled_at
    ])
    |> validate_required([:user_id, :plan_id, :stripe_customer_id, :status])
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:plan_id)
  end

  @doc """
  Returns true if the subscription is active (i.e., the user has access to the plan)
  """
  def active?(%__MODULE__{status: status}) do
    status in ["active", "trialing"]
  end
end
