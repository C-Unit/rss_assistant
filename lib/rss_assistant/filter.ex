defmodule RssAssistant.Filter do
  @moduledoc """
  Behavior for filtering RSS feed items based on user prompts.

  Implementations can use various strategies (LLM-based, keyword-based, etc.)
  to determine whether an item should be included in the filtered feed.
  """

  alias RssAssistant.{FeedItem, FeedItemDecision}

  @doc """
  Determines whether an RSS item should be included in the filtered feed.

  ## Parameters

    * `item` - The RSS item to evaluate
    * `prompt` - The user's filtering prompt describing what to filter out

  ## Returns

    * `%FeedItemDecision{}` struct containing the decision, reasoning, and item_id
  """
  @callback should_include?(item :: FeedItem.t(), prompt :: String.t()) :: FeedItemDecision.t()
end
