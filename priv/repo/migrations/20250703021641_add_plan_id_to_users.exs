defmodule RssAssistant.Repo.Migrations.AddPlanIdToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :plan_id, references(:plans, on_delete: :nothing), null: false
    end

    create index(:users, [:plan_id])
  end
end
