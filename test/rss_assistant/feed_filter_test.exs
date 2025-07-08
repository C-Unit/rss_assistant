defmodule RssAssistant.FeedFilterTest do
  use RssAssistant.DataCase

  import Mox
  import ExUnit.CaptureLog
  import RssAssistant.AccountsFixtures

  alias RssAssistant.{FeedFilter, FeedItem, FilteredFeed, Repo}

  # Make sure mocks are verified when the test exits
  setup :verify_on_exit!

  setup do
    # Ensure plans exist and create user
    free_plan_fixture()
    user = user_fixture()

    # Create a test filtered feed
    {:ok, filtered_feed} =
      %FilteredFeed{}
      |> FilteredFeed.changeset(%{
        url: "https://example.com/test.xml",
        prompt: "test filtering",
        user_id: user.id
      })
      |> Repo.insert()

    %{filtered_feed_id: filtered_feed.id}
  end

  describe "filter_feed/3" do
    test "filters RSS feed based on mock filter behavior", %{filtered_feed_id: filtered_feed_id} do
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
        %FeedItem{title: "Include This"}, "test prompt" ->
          {:ok, {true, "Should include"}}

        %FeedItem{title: "Exclude This"}, "test prompt" ->
          {:ok, {false, "Should exclude"}}
      end)

      assert {:ok, filtered_xml} =
               FeedFilter.filter_feed(rss_xml, "test prompt", filtered_feed_id)

      # Verify the filtered XML contains only the included item
      assert filtered_xml =~ "Include This"
      refute filtered_xml =~ "Exclude This"
      assert filtered_xml =~ "<rss version=\"2.0\">"
      assert filtered_xml =~ "<channel>"
    end

    test "includes all items when filter always returns true", %{
      filtered_feed_id: filtered_feed_id
    } do
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

      expect(RssAssistant.Filter.Mock, :should_include?, 2, fn _, _ ->
        {:ok, {true, "Include all"}}
      end)

      assert {:ok, filtered_xml} =
               FeedFilter.filter_feed(rss_xml, "include all", filtered_feed_id)

      assert filtered_xml =~ "Item 1"
      assert filtered_xml =~ "Item 2"
    end

    test "excludes all items when filter always returns false", %{
      filtered_feed_id: filtered_feed_id
    } do
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

      expect(RssAssistant.Filter.Mock, :should_include?, 1, fn _, _ ->
        {:ok, {false, "Exclude all"}}
      end)

      assert {:ok, filtered_xml} =
               FeedFilter.filter_feed(rss_xml, "exclude all", filtered_feed_id)

      refute filtered_xml =~ "Item 1"
      # Channel metadata should still be present
      assert filtered_xml =~ "<channel>"
    end

    test "handles invalid XML gracefully", %{filtered_feed_id: filtered_feed_id} do
      capture_log(fn ->
        assert {:error, :invalid_xml} =
                 FeedFilter.filter_feed("invalid xml", "test", filtered_feed_id)
      end)

      assert {:error, :invalid_input} = FeedFilter.filter_feed(nil, "test", filtered_feed_id)
      assert {:error, :invalid_input} = FeedFilter.filter_feed("valid", nil, filtered_feed_id)
    end

    test "handles Atom feeds", %{filtered_feed_id: filtered_feed_id} do
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

      expect(RssAssistant.Filter.Mock, :should_include?, 1, fn _, _ ->
        {:ok, {true, "Include atom entry"}}
      end)

      assert {:ok, filtered_xml} = FeedFilter.filter_feed(atom_xml, "test", filtered_feed_id)

      assert filtered_xml =~ "Atom Entry"
      assert filtered_xml =~ "<feed"
      assert filtered_xml =~ "xmlns=\"http://www.w3.org/2005/Atom\""
    end
  end

  describe "retry functionality" do
    test "retries when filter returns {:retry, delay}", %{filtered_feed_id: filtered_feed_id} do
      rss_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <description>A test feed</description>
          <item>
            <title>Test Item</title>
            <description>Test description</description>
            <link>https://example.com/test</link>
            <guid>test-1</guid>
          </item>
        </channel>
      </rss>
      """

      # First call returns retry, second call returns success
      ref = make_ref()
      expect(RssAssistant.Filter.Mock, :should_include?, 2, fn _, _ ->
        case Process.get(ref, {1, nil}) do
          {1, _} ->
            start_time = System.monotonic_time(:millisecond)
            Process.put(ref, {2, start_time})
            {:retry, 100}  # 100ms delay
          {2, start_time} ->
            current_time = System.monotonic_time(:millisecond)
            assert current_time - start_time >= 100, "Second call should be at least 100ms later"
            {:ok, {true, "Included after retry"}}
        end
      end)

      assert {:ok, filtered_xml} = FeedFilter.filter_feed(rss_xml, "test", filtered_feed_id)
      assert filtered_xml =~ "Test Item"
    end

    test "handles failed retry gracefully", %{filtered_feed_id: filtered_feed_id} do
      rss_xml = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <description>A test feed</description>
          <item>
            <title>Test Item</title>
            <description>Test description</description>
            <link>https://example.com/test</link>
            <guid>test-1</guid>
          </item>
        </channel>
      </rss>
      """

      # First call returns retry, second call returns error
      ref = make_ref()
      expect(RssAssistant.Filter.Mock, :should_include?, 2, fn _, _ ->
        case Process.get(ref, {1, nil}) do
          {1, _} ->
            Process.put(ref, {2, nil})
            {:retry, 100}
          {2, _} ->
            {:error, :api_failed}
        end
      end)

      # Should still return filtered XML (item included by default when filter fails)
      assert {:ok, filtered_xml} = FeedFilter.filter_feed(rss_xml, "test", filtered_feed_id)
      assert filtered_xml =~ "Test Item"
    end
  end
end
