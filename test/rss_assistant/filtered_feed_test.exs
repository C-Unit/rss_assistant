defmodule RssAssistant.FilteredFeedTest do
  use RssAssistant.DataCase

  alias RssAssistant.FilteredFeed

  describe "changeset/2" do
    test "validates required fields" do
      changeset = FilteredFeed.changeset(%FilteredFeed{}, %{})
      
      assert changeset.errors[:url] == {"can't be blank", [validation: :required]}
      assert changeset.errors[:prompt] == {"can't be blank", [validation: :required]}
    end

    test "validates URL format" do
      changeset = FilteredFeed.changeset(%FilteredFeed{}, %{
        url: "not-a-url",
        prompt: "Filter out sports content"
      })
      
      assert changeset.errors[:url] == {"must be a valid URL", [validation: :format]}
    end

    test "accepts valid HTTP URLs" do
      changeset = FilteredFeed.changeset(%FilteredFeed{}, %{
        url: "http://example.com/feed.xml",
        prompt: "Filter out sports content"
      })
      
      assert changeset.valid?
    end

    test "accepts valid HTTPS URLs" do
      changeset = FilteredFeed.changeset(%FilteredFeed{}, %{
        url: "https://example.com/feed.xml",
        prompt: "Filter out sports content"
      })
      
      assert changeset.valid?
    end

    test "generates a slug automatically" do
      changeset = FilteredFeed.changeset(%FilteredFeed{}, %{
        url: "https://example.com/feed.xml",
        prompt: "Filter out sports content"
      })
      
      {:ok, filtered_feed} = apply_action(changeset, :insert)
      
      assert filtered_feed.slug != nil
      assert String.length(filtered_feed.slug) == 8
    end

    test "does not generate slug if changeset is invalid" do
      changeset = FilteredFeed.changeset(%FilteredFeed{}, %{
        url: "not-a-url",
        prompt: "Filter out sports content"
      })
      
      refute changeset.valid?
      assert get_change(changeset, :slug) == nil
    end
  end
end