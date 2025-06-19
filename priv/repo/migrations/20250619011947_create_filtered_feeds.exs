defmodule RssAssistant.Repo.Migrations.CreateFilteredFeeds do
  use Ecto.Migration

  def change do
    create table(:filtered_feeds) do
      add :url, :string, null: false
      add :prompt, :text, null: false
      add :slug, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:filtered_feeds, [:slug])
  end
end
