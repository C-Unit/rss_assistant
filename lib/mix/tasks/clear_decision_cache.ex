defmodule Mix.Tasks.ClearDecisionCache do
  @moduledoc """
  Mix task to clear the decision cache by deleting all feed item decisions.

  ## Usage

      mix clear_decision_cache

  This will delete all records from the feed_item_decisions table.
  """
  use Mix.Task

  alias RssAssistant.Repo
  alias RssAssistant.FeedItemDecision

  @requirements ["app.start"]
  @shortdoc "Clear the decision cache"

  @impl Mix.Task
  def run(_args) do
    {count, _} = Repo.delete_all(FeedItemDecision)
    Mix.shell().info("Cleared #{count} cached decisions")
  end
end
