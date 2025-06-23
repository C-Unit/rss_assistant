defmodule RssAssistant.Filter.AlwaysInclude do
  @moduledoc """
  A simple filter implementation that always includes all items.

  This is useful for development and testing, or as a fallback
  when the actual filtering service is unavailable.
  """

  @behaviour RssAssistant.Filter

  alias RssAssistant.{FeedItem, FeedItemDecision}

  @impl RssAssistant.Filter
  def should_include?(%FeedItem{} = item, _prompt) do
    decision = FeedItemDecision.new(item.generated_id, true, "Always include filter")
    {:ok, decision}
  end
end
