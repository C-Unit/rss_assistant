defmodule RssAssistant.FeedFilterTest do
  use ExUnit.Case, async: true

  import Mox

  alias RssAssistant.{FeedFilter, RssItem}

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  describe "filter_feed/2" do
    test "filters RSS feed based on mock filter behavior" do
      rss_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <description>A test feed</description>
          <item>
            <title>Include This</title>
            <description>This should be included</description>
            <link>https://example.com/include</link>
            <guid>include-1</guid>
          </item>
          <item>
            <title>Exclude This</title>
            <description>This should be excluded</description>
            <link>https://example.com/exclude</link>
            <guid>exclude-1</guid>
          </item>
        </channel>
      </rss>
      """

      # Mock the filter to include first item, exclude second
      expect(RssAssistant.Filter.Mock, :should_include?, 2, fn
        %RssItem{title: "Include This"}, "test prompt" -> true
        %RssItem{title: "Exclude This"}, "test prompt" -> false
      end)

      assert {:ok, filtered_xml} = FeedFilter.filter_feed(rss_xml, "test prompt")

      # Verify the filtered XML contains only the included item
      assert filtered_xml =~ "Include This"
      refute filtered_xml =~ "Exclude This"
      assert filtered_xml =~ "<rss version=\"2.0\">"
      assert filtered_xml =~ "<channel>"
    end

    test "includes all items when filter always returns true" do
      rss_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <item>
            <title>Item 1</title>
            <guid>item-1</guid>
          </item>
          <item>
            <title>Item 2</title>
            <guid>item-2</guid>
          </item>
        </channel>
      </rss>
      """

      expect(RssAssistant.Filter.Mock, :should_include?, 2, fn _, _ -> true end)

      assert {:ok, filtered_xml} = FeedFilter.filter_feed(rss_xml, "include all")

      assert filtered_xml =~ "Item 1"
      assert filtered_xml =~ "Item 2"
    end

    test "excludes all items when filter always returns false" do
      rss_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <item>
            <title>Item 1</title>
            <guid>item-1</guid>
          </item>
        </channel>
      </rss>
      """

      expect(RssAssistant.Filter.Mock, :should_include?, 2, fn _, _ -> false end)

      assert {:ok, filtered_xml} = FeedFilter.filter_feed(rss_xml, "exclude all")

      refute filtered_xml =~ "Item 1"
      # Channel metadata should still be present
      assert filtered_xml =~ "<channel>"
    end

    test "handles invalid XML gracefully" do
      assert {:error, :invalid_xml} = FeedFilter.filter_feed("invalid xml", "test")
      assert {:error, :invalid_input} = FeedFilter.filter_feed(nil, "test")
      assert {:error, :invalid_input} = FeedFilter.filter_feed("valid", nil)
    end

    test "handles Atom feeds" do
      atom_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Test Atom Feed</title>
        <entry>
          <title>Atom Entry</title>
          <id>atom-1</id>
        </entry>
      </feed>
      """

      expect(RssAssistant.Filter.Mock, :should_include?, 2, fn _, _ -> true end)

      assert {:ok, filtered_xml} = FeedFilter.filter_feed(atom_xml, "test")

      assert filtered_xml =~ "Atom Entry"
      assert filtered_xml =~ "<feed"
      assert filtered_xml =~ "xmlns=\"http://www.w3.org/2005/Atom\""
    end
  end
end
