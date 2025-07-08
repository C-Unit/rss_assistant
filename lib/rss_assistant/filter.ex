defmodule RssAssistant.Filter do
  @moduledoc """
  Behavior for filtering RSS feed items based on user prompts.

  Implementations can use various strategies (LLM-based, keyword-based, etc.)
  to determine whether an item should be included in the filtered feed.
  """

  alias RssAssistant.FeedItem

  @doc """
  Determines whether an RSS item should be included in the filtered feed.

  ## Parameters

    * `item` - The RSS item to evaluate
    * `prompt` - The user's filtering prompt describing what to filter out

  ## Returns

    * `{:ok, {should_include, reasoning}}` - Successful decision with boolean and reasoning
    * `{:retry, retry_after_seconds}` - Rate limited, retry after specified seconds
    * `{:error, reason}` - Error reason when filter implementation fails
  """
  @callback should_include?(item :: FeedItem.t(), prompt :: String.t()) ::
              {:ok, {boolean(), String.t()}} | {:retry, non_neg_integer()} | {:error, term()}
end
