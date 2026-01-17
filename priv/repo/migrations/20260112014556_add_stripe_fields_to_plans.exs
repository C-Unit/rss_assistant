defmodule RssAssistant.Repo.Migrations.AddStripeFieldsToPlans do
  use Ecto.Migration

  def change do
    alter table(:plans) do
      add :stripe_price_id, :string
      add :stripe_product_id, :string
    end
  end
end
