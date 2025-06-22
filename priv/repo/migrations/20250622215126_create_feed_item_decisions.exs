defmodule RssAssistant.Repo.Migrations.CreateFeedItemDecisions do
  use Ecto.Migration

  def change do
    create table(:feed_item_decisions) do
      add :item_id, :string, null: false
      add :should_include, :boolean, null: false
      add :reasoning, :text
      add :filtered_feed_id, references(:filtered_feeds, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:feed_item_decisions, [:item_id, :filtered_feed_id])
    create index(:feed_item_decisions, [:filtered_feed_id])
  end
end
