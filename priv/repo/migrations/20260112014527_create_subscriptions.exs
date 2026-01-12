defmodule RssAssistant.Repo.Migrations.CreateSubscriptions do
  use Ecto.Migration

  def change do
    create table(:subscriptions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :plan_id, references(:plans, on_delete: :restrict), null: false

      # Stripe identifiers
      add :stripe_customer_id, :string, null: false
      add :stripe_subscription_id, :string
      add :stripe_price_id, :string

      # Subscription state
      add :status, :string, null: false, default: "incomplete"
      add :current_period_start, :naive_datetime
      add :current_period_end, :naive_datetime
      add :cancel_at_period_end, :boolean, default: false, null: false
      add :canceled_at, :naive_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:subscriptions, [:user_id])
    create index(:subscriptions, [:stripe_customer_id])
    create index(:subscriptions, [:stripe_subscription_id])
    create index(:subscriptions, [:status])
  end
end
