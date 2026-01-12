defmodule RssAssistant.Repo.Migrations.AddStripePriceIdToPlans do
  use Ecto.Migration

  def change do
    alter table(:plans) do
      add :stripe_price_id, :string
    end

    create unique_index(:plans, [:stripe_price_id])
  end
end
