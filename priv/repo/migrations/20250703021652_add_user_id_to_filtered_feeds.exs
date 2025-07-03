defmodule RssAssistant.Repo.Migrations.AddUserIdToFilteredFeeds do
  use Ecto.Migration

  def change do
    alter table(:filtered_feeds) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
    end

    create index(:filtered_feeds, [:user_id])
  end
end
