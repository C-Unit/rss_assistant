defmodule RssAssistant.IntegrationTest do
  use RssAssistant.DataCase

  import Mox

  alias RssAssistant.{FeedParser, FeedFilter, FeedItem, FeedItemDecision, FilteredFeed, Repo}

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Create a test filtered feed
    {:ok, filtered_feed} = 
      %FilteredFeed{}
      |> FilteredFeed.changeset(%{
        url: "https://example.com/nytimes.xml",
        prompt: "integration test filtering"
      })
      |> Repo.insert()

    %{filtered_feed_id: filtered_feed.id}
  end

  @nytimes_sample_xml """
  <?xml version="1.0" encoding="UTF-8"?>
  <rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:media="http://search.yahoo.com/mrss/" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:nyt="http://www.nytimes.com/namespaces/rss/2.0" version="2.0">
    <channel>
      <title>NYT &gt; Top Stories</title>
      <link>https://www.nytimes.com</link>
      <atom:link href="https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml" rel="self" type="application/rss+xml"></atom:link>
      <description></description>
      <language>en-us</language>
      <copyright>Copyright 2025 The New York Times Company</copyright>
      <lastBuildDate>Thu, 19 Jun 2025 20:14:08 +0000</lastBuildDate>
      <pubDate>Thu, 19 Jun 2025 20:02:31 +0000</pubDate>
      <item>
        <title>Europe to Hold Talks With Iran on Friday</title>
        <link>https://www.nytimes.com/2025/06/19/world/europe/europe-iran-israel-war-talks-nuclear.html</link>
        <guid isPermaLink="true">https://www.nytimes.com/2025/06/19/world/europe/europe-iran-israel-war-talks-nuclear.html</guid>
        <description><![CDATA[European officials hope discussions will lead to de-escalation after devastating wars.]]></description>
        <dc:creator>Steven Erlanger</dc:creator>
        <pubDate>Thu, 19 Jun 2025 19:45:31 +0000</pubDate>
        <category domain="http://www.nytimes.com/namespaces/keywords/des">International Relations</category>
        <category domain="http://www.nytimes.com/namespaces/keywords/des">War and Armed Conflicts</category>
      </item>
      <item>
        <title>Sports: New Stadium Opens in Major City</title>
        <link>https://www.nytimes.com/2025/06/19/sports/stadium-opening.html</link>
        <guid isPermaLink="true">https://www.nytimes.com/2025/06/19/sports/stadium-opening.html</guid>
        <description><![CDATA[A new multi-billion dollar stadium welcomes its first game.]]></description>
        <dc:creator>Sports Reporter</dc:creator>
        <pubDate>Thu, 19 Jun 2025 18:30:00 +0000</pubDate>
        <category domain="http://www.nytimes.com/namespaces/keywords/des">Sports</category>
        <category domain="http://www.nytimes.com/namespaces/keywords/des">Architecture</category>
      </item>
      <item>
        <title>Technology: AI Breakthrough Announced</title>
        <link>https://www.nytimes.com/2025/06/19/technology/ai-breakthrough.html</link>
        <guid isPermaLink="true">https://www.nytimes.com/2025/06/19/technology/ai-breakthrough.html</guid>
        <description><![CDATA[Researchers announce major advancement in artificial intelligence.]]></description>
        <dc:creator>Tech Reporter</dc:creator>
        <pubDate>Thu, 19 Jun 2025 17:15:00 +0000</pubDate>
        <category domain="http://www.nytimes.com/namespaces/keywords/des">Technology</category>
        <category domain="http://www.nytimes.com/namespaces/keywords/des">Artificial Intelligence</category>
      </item>
    </channel>
  </rss>
  """

  describe "end-to-end feed filtering" do
    test "parses real RSS feed structure correctly" do
      assert {:ok, items} = FeedParser.parse_feed(@nytimes_sample_xml)
      assert length(items) == 3

      [iran_item, sports_item, tech_item] = items

      # Verify the Iran item
      assert %FeedItem{
               title: "Europe to Hold Talks With Iran on Friday",
               description:
                 "European officials hope discussions will lead to de-escalation after devastating wars.",
               link:
                 "https://www.nytimes.com/2025/06/19/world/europe/europe-iran-israel-war-talks-nuclear.html",
               categories: ["International Relations", "War and Armed Conflicts"]
             } = iran_item

      # Verify the sports item
      assert %FeedItem{
               title: "Sports: New Stadium Opens in Major City",
               categories: ["Sports", "Architecture"]
             } = sports_item

      # Verify the tech item
      assert %FeedItem{
               title: "Technology: AI Breakthrough Announced",
               categories: ["Technology", "Artificial Intelligence"]
             } = tech_item
    end

    test "filters out sports content", %{filtered_feed_id: filtered_feed_id} do
      # Mock filter to exclude sports-related content
      expect(RssAssistant.Filter.Mock, :should_include?, 2, fn
        %FeedItem{title: title} = item, "filter out sports content" ->
          should_include = not (title |> String.downcase() |> String.contains?("sports"))
          decision = %FeedItemDecision{
            item_id: item.generated_id, 
            should_include: should_include, 
            reasoning: if(should_include, do: "Not sports", else: "Sports content")
          }
          {:ok, decision}
      end)

      assert {:ok, filtered_xml} =
               FeedFilter.filter_feed(@nytimes_sample_xml, "filter out sports content", filtered_feed_id)

      # Should include Iran and Tech stories
      assert filtered_xml =~ "Europe to Hold Talks With Iran on Friday"
      assert filtered_xml =~ "Technology: AI Breakthrough Announced"

      # Should exclude sports story
      refute filtered_xml =~ "Sports: New Stadium Opens"

      # Should maintain RSS structure
      assert filtered_xml =~ "<rss"
      assert filtered_xml =~ "<channel>"
      assert filtered_xml =~ "NYT &gt; Top Stories"
    end

    test "includes all content when no filtering", %{filtered_feed_id: filtered_feed_id} do
      # Mock filter to include everything
      expect(RssAssistant.Filter.Mock, :should_include?, 2, fn item, _ -> 
        {:ok, %FeedItemDecision{item_id: item.generated_id, should_include: true, reasoning: "Include all"}}
      end)

      assert {:ok, filtered_xml} =
               FeedFilter.filter_feed(@nytimes_sample_xml, "include everything", filtered_feed_id)

      # Should include all stories
      assert filtered_xml =~ "Europe to Hold Talks With Iran on Friday"
      assert filtered_xml =~ "Sports: New Stadium Opens in Major City"
      assert filtered_xml =~ "Technology: AI Breakthrough Announced"
    end

    test "excludes all content when aggressive filtering", %{filtered_feed_id: filtered_feed_id} do
      # Mock filter to exclude everything
      expect(RssAssistant.Filter.Mock, :should_include?, 3, fn item, _ -> 
        {:ok, %FeedItemDecision{item_id: item.generated_id, should_include: false, reasoning: "Exclude all"}}
      end)

      assert {:ok, filtered_xml} =
               FeedFilter.filter_feed(@nytimes_sample_xml, "exclude everything", filtered_feed_id)

      # Should exclude all stories
      refute filtered_xml =~ "Europe to Hold Talks With Iran on Friday"
      refute filtered_xml =~ "Sports: New Stadium Opens in Major City"
      refute filtered_xml =~ "Technology: AI Breakthrough Announced"

      # But should maintain feed structure
      assert filtered_xml =~ "<rss"
      assert filtered_xml =~ "<channel>"
      assert filtered_xml =~ "NYT &gt; Top Stories"
    end

    test "preserves RSS metadata and structure", %{filtered_feed_id: filtered_feed_id} do
      expect(RssAssistant.Filter.Mock, :should_include?, 2, fn item, _ -> 
        {:ok, %FeedItemDecision{item_id: item.generated_id, should_include: true, reasoning: "Preserve structure test"}}
      end)

      assert {:ok, filtered_xml} = FeedFilter.filter_feed(@nytimes_sample_xml, "test", filtered_feed_id)

      # Check RSS metadata is preserved
      assert filtered_xml =~ "NYT &gt; Top Stories"
      assert filtered_xml =~ "https://www.nytimes.com"
      assert filtered_xml =~ "en-us"
      assert filtered_xml =~ "Copyright 2025 The New York Times Company"

      # Check structure
      assert filtered_xml =~ "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
      assert filtered_xml =~ "<rss version=\"2.0\">"
      assert filtered_xml =~ "</rss>"
    end
  end
end
