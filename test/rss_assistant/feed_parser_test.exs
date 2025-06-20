defmodule RssAssistant.FeedParserTest do
  use ExUnit.Case, async: true

  alias RssAssistant.{FeedParser, RssItem}

  describe "parse_feed/1" do
    test "parses RSS 2.0 feed successfully" do
      rss_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <description>A test feed</description>
          <item>
            <title>First Item</title>
            <description>First item description</description>
            <link>https://example.com/1</link>
            <pubDate>Mon, 06 Sep 2021 16:45:00 GMT</pubDate>
            <guid>item-1</guid>
            <category>Tech</category>
            <category>News</category>
          </item>
          <item>
            <title>Second Item</title>
            <description>Second item description</description>
            <link>https://example.com/2</link>
            <guid>item-2</guid>
          </item>
        </channel>
      </rss>
      """

      assert {:ok, items} = FeedParser.parse_feed(rss_xml)
      assert length(items) == 2

      [first_item, second_item] = items

      assert %RssItem{
               id: "item-1",
               title: "First Item",
               description: "First item description",
               link: "https://example.com/1",
               pub_date: "Mon, 06 Sep 2021 16:45:00 GMT",
               guid: "item-1",
               categories: ["Tech", "News"]
             } = first_item

      assert %RssItem{
               id: "item-2",
               title: "Second Item",
               description: "Second item description",
               link: "https://example.com/2",
               guid: "item-2",
               categories: []
             } = second_item
    end

    test "parses Atom feed successfully" do
      atom_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Test Atom Feed</title>
        <entry>
          <title>Atom Entry</title>
          <summary>Atom entry summary</summary>
          <link href="https://example.com/atom/1" rel="alternate"/>
          <published>2021-09-06T16:45:00Z</published>
          <id>atom-entry-1</id>
          <category term="Science"/>
        </entry>
      </feed>
      """

      assert {:ok, items} = FeedParser.parse_feed(atom_xml)
      assert length(items) == 1

      [item] = items

      assert %RssItem{
               id: "atom-entry-1",
               title: "Atom Entry",
               description: "Atom entry summary",
               link: "https://example.com/atom/1",
               pub_date: "2021-09-06T16:45:00Z",
               guid: "atom-entry-1",
               categories: ["Science"]
             } = item
    end

    test "handles invalid XML" do
      assert {:error, :invalid_xml} = FeedParser.parse_feed("invalid xml")
      assert {:error, :invalid_xml} = FeedParser.parse_feed(nil)
      assert {:error, :invalid_xml} = FeedParser.parse_feed(123)
    end

    test "handles empty feed" do
      empty_rss = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Empty Feed</title>
        </channel>
      </rss>
      """

      assert {:ok, []} = FeedParser.parse_feed(empty_rss)
    end
  end
end
