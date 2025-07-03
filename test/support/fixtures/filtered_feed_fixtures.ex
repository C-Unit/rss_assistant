defmodule RssAssistant.FilteredFeedFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `RssAssistant.FilteredFeed` context.
  """

  import RssAssistant.AccountsFixtures

  def valid_filtered_feed_attributes(attrs \\ %{}) do
    # Only create a user if user_id is not provided
    default_attrs = %{
      url: "https://example.com/feed.xml",
      prompt: "Filter out sports content"
    }
    
    attrs = Enum.into(attrs, default_attrs)
    
    # Add user_id if not provided
    if Map.has_key?(attrs, :user_id) do
      attrs
    else
      user = user_fixture()
      Map.put(attrs, :user_id, user.id)
    end
  end

  def filtered_feed_fixture(attrs \\ %{}) do
    %RssAssistant.FilteredFeed{}
    |> RssAssistant.FilteredFeed.changeset(valid_filtered_feed_attributes(attrs))
    |> RssAssistant.Repo.insert!()
  end
end