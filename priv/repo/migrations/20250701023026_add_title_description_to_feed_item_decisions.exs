defmodule RssAssistant.Repo.Migrations.AddTitleDescriptionToFeedItemDecisions do
  use Ecto.Migration

  def change do
    alter table(:feed_item_decisions) do
      add :title, :text
      add :description, :text
    end
  end
end
