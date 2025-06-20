defmodule RssAssistant.FeedItemTest do
  use ExUnit.Case, async: true

  alias RssAssistant.FeedItem

  describe "generate_id/1" do
    test "uses guid when available" do
      item = %{guid: "test-guid-123"}
      assert FeedItem.generate_id(item) == {:ok, "test-guid-123"}
    end

    test "generates hash from link and title when no guid" do
      item = %{link: "https://example.com", title: "Test Title", guid: nil}
      assert {:ok, id} = FeedItem.generate_id(item)

      assert is_binary(id)
      assert String.length(id) == 16
      # Should be deterministic
      assert FeedItem.generate_id(item) == {:ok, id}

      # Assert the actual expected value
      assert id == "4695c1ca97d4ef0c"
    end

    test "generates hash from link only when no title" do
      item = %{link: "https://example.com", title: nil, guid: nil}
      assert {:ok, id} = FeedItem.generate_id(item)

      assert is_binary(id)
      assert String.length(id) == 16

      # Assert the actual expected value
      assert id == "100680ad546ce6a5"
    end

    test "returns error when no guid, link, or title available" do
      item = %{link: nil, title: nil, guid: nil}
      assert {:error, :no_identifiable_content} = FeedItem.generate_id(item)

      # Should be consistent - same error every time for same input
      assert FeedItem.generate_id(item) == {:error, :no_identifiable_content}
    end

    test "generates hash from title when no guid or link" do
      item = %{link: nil, title: "Test Title", guid: nil}
      assert {:ok, id} = FeedItem.generate_id(item)

      assert is_binary(id)
      assert String.length(id) == 16

      # Should be deterministic
      assert FeedItem.generate_id(item) == {:ok, id}

      # Assert the actual expected value
      assert id == "9775c7702cac35e8"
    end
  end
end
