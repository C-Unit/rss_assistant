defmodule RssAssistant.Repo.Migrations.AddStripeFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :stripe_customer_id, :string
      add :stripe_subscription_id, :string
      add :stripe_subscription_status, :string
    end

    create unique_index(:users, [:stripe_customer_id])
    create index(:users, [:stripe_subscription_id])
  end
end
