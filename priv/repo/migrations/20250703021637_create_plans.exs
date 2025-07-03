defmodule RssAssistant.Repo.Migrations.CreatePlans do
  use Ecto.Migration

  def change do
    create table(:plans) do
      add :name, :string
      add :max_feeds, :integer
      add :price, :decimal

      timestamps(type: :utc_datetime)
    end
  end
end
