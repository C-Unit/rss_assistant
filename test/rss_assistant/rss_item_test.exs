defmodule RssAssistant.RssItemTest do
  use ExUnit.Case, async: true

  alias RssAssistant.RssItem

  describe "generate_id/1" do
    test "uses guid when available" do
      item = %{guid: "test-guid-123"}
      assert RssItem.generate_id(item) == "test-guid-123"
    end

    test "generates hash from link and title when no guid" do
      item = %{link: "https://example.com", title: "Test Title", guid: nil}
      id = RssItem.generate_id(item)

      assert is_binary(id)
      assert String.length(id) == 16
      # Should be deterministic
      assert RssItem.generate_id(item) == id

      # Assert the actual expected value
      assert id == "4695c1ca97d4ef0c"
    end

    test "generates hash from link only when no title" do
      item = %{link: "https://example.com", title: nil, guid: nil}
      id = RssItem.generate_id(item)

      assert is_binary(id)
      assert String.length(id) == 16

      # Assert the actual expected value
      assert id == "100680ad546ce6a5"
    end

    test "generates deterministic fallback id when no guid, link, or title" do
      item = %{link: nil, title: nil, guid: nil}
      id = RssItem.generate_id(item)

      assert is_binary(id)
      assert String.length(id) == 16

      # Should be deterministic - same ID every time for same input
      id2 = RssItem.generate_id(item)
      assert id == id2

      # Assert the actual expected fallback value
      assert id == "3577728c44258a81"
    end

    test "generates hash from title when no guid or link" do
      item = %{link: nil, title: "Test Title", guid: nil}
      id = RssItem.generate_id(item)

      assert is_binary(id)
      assert String.length(id) == 16

      # Should be deterministic
      assert RssItem.generate_id(item) == id

      # Assert the actual expected value
      assert id == "9775c7702cac35e8"
    end
  end
end
