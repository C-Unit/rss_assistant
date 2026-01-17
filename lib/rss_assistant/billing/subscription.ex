defmodule RssAssistant.Billing.Subscription do
  @moduledoc """
  Subscription schema for tracking Stripe subscriptions.
  """

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

    timestamps(type: :utc_datetime)
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
  Returns true if subscription grants access to the plan.

  Active if: status is active/trialing AND (not canceling OR period hasn't ended)
  """
  def active?(%__MODULE__{} = subscription) do
    subscription.status in ["active", "trialing"] and
      (!subscription.cancel_at_period_end or
         period_not_ended?(subscription.current_period_end))
  end

  defp period_not_ended?(nil), do: false

  defp period_not_ended?(period_end) do
    NaiveDateTime.compare(NaiveDateTime.utc_now(), period_end) == :lt
  end
end
