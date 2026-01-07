defmodule RssAssistant.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :rss_assistant

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  def upgrade_all_users_to_pro do
    load_app()
    Application.ensure_all_started(@app)

    alias RssAssistant.Accounts
    alias RssAssistant.Repo

    # Get the Pro plan
    pro_plan = Accounts.get_plan_by_name("Pro")

    if is_nil(pro_plan) do
      IO.puts("ERROR: Pro plan not found in database!")
      {:error, :plan_not_found}
    else
      do_upgrade_users_to_pro(Repo.all(Accounts.User), pro_plan)
    end
  end

  defp do_upgrade_users_to_pro(users, pro_plan) do
    alias RssAssistant.Accounts

    IO.puts("Upgrading #{length(users)} users to Pro plan...")

    IO.puts(
      "Plan: #{pro_plan.name} (max_feeds: #{pro_plan.max_feeds}, price: $#{pro_plan.price})"
    )

    IO.puts("")

    results = Enum.map(users, &upgrade_user_to_plan(&1, pro_plan.id))

    success_count = Enum.count(results, &(&1 == :ok))
    failure_count = Enum.count(results, &(&1 == :error))

    print_upgrade_summary(length(users), success_count, failure_count)

    {:ok, %{total: length(users), success: success_count, failed: failure_count}}
  end

  defp upgrade_user_to_plan(user, pro_plan_id) do
    alias RssAssistant.Accounts

    current_plan = user.plan_id

    case Accounts.change_user_plan(user, pro_plan_id) do
      {:ok, _updated_user} ->
        IO.puts("✓ Upgraded user #{user.email} (plan_id: #{current_plan} -> #{pro_plan_id})")
        :ok

      {:error, changeset} ->
        IO.puts("✗ Failed to upgrade user #{user.email}: #{inspect(changeset.errors)}")
        :error
    end
  end

  defp print_upgrade_summary(total, success_count, failure_count) do
    IO.puts("")
    IO.puts("=" |> String.duplicate(60))
    IO.puts("SUMMARY")
    IO.puts("=" |> String.duplicate(60))
    IO.puts("Total users: #{total}")
    IO.puts("Successfully upgraded: #{success_count}")
    IO.puts("Failed: #{failure_count}")
    IO.puts("=" |> String.duplicate(60))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
