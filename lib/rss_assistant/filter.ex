defmodule RssAssistant.Filter do
  @moduledoc """
  Behavior for filtering RSS feed items based on user prompts.

  Implementations can use various strategies (LLM-based, keyword-based, etc.)
  to determine whether an item should be included in the filtered feed.
  """

  alias RssAssistant.RssItem

  @doc """
  Determines whether an RSS item should be included in the filtered feed.

  ## Parameters

    * `item` - The RSS item to evaluate
    * `prompt` - The user's filtering prompt describing what to filter out

  ## Returns

    * `true` if the item should be included
    * `false` if the item should be filtered out
  """
  @callback should_include?(item :: RssItem.t(), prompt :: String.t()) :: boolean()
end
