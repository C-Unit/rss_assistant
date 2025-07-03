defmodule RssAssistant.FeedFilterCachingTest do
  use RssAssistant.DataCase
  
  import Mox
  import RssAssistant.AccountsFixtures
  
  alias RssAssistant.{FeedFilter, FeedItem, FeedItemDecision, FeedItemDecisionSchema, FilteredFeed, Repo}

  # Define our mock filter behaviour
  defmock(MockFilter, for: RssAssistant.Filter)

  setup :verify_on_exit!

  setup do
    # Configure the application to use our mock filter
    original_filter = Application.get_env(:rss_assistant, :filter_impl)
    Application.put_env(:rss_assistant, :filter_impl, MockFilter)
    
    # Ensure plans exist and create user
    free_plan_fixture()
    user = user_fixture()
    
    # Create a filtered feed for testing
    {:ok, filtered_feed} = 
      %FilteredFeed{}
      |> FilteredFeed.changeset(%{
        url: "https://example.com/feed.xml",
        prompt: "filter test content",
        user_id: user.id
      })
      |> Repo.insert()

    # Sample RSS content
    rss_content = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>Test Feed</title>
        <description>Test Description</description>
        <link>https://example.com</link>
        <item>
          <title>Test Item 1</title>
          <description>First test item</description>
          <link>https://example.com/item1</link>
          <guid>item1-guid</guid>
        </item>
        <item>
          <title>Test Item 2</title>
          <description>Second test item</description>
          <link>https://example.com/item2</link>
          <guid>item2-guid</guid>
        </item>
        <item>
          <title>Test Item 3</title>
          <description>Third test item with no identifiable content</description>
        </item>
      </channel>
    </rss>
    """

    on_exit(fn ->
      # Restore original filter configuration
      Application.put_env(:rss_assistant, :filter_impl, original_filter)
    end)

    %{
      filtered_feed: filtered_feed,
      rss_content: rss_content,
      prompt: "test filtering prompt"
    }
  end

  describe "decision caching" do
    test "first evaluation calls filter and caches decision", %{filtered_feed: filtered_feed, rss_content: rss_content, prompt: prompt} do
      # Setup mock expectations
      MockFilter
      |> expect(:should_include?, fn %FeedItem{generated_id: "item1-guid"}, ^prompt ->
        {:ok, %FeedItemDecision{
          item_id: "item1-guid",
          should_include: true,
          reasoning: "Test reasoning for item 1"
        }}
      end)
      |> expect(:should_include?, fn %FeedItem{generated_id: "item2-guid"}, ^prompt ->
        {:ok, %FeedItemDecision{
          item_id: "item2-guid", 
          should_include: false,
          reasoning: "Test reasoning for item 2"
        }}
      end)

      # First call should invoke the filter
      {:ok, _filtered_xml} = FeedFilter.filter_feed(rss_content, prompt, filtered_feed.id)

      # Verify decisions were stored in database
      decisions = Repo.all(FeedItemDecisionSchema)
      assert length(decisions) == 2
      
      item1_decision = Enum.find(decisions, &(&1.item_id == "item1-guid"))
      assert item1_decision.should_include == true
      assert item1_decision.reasoning == "Test reasoning for item 1"
      assert item1_decision.filtered_feed_id == filtered_feed.id

      item2_decision = Enum.find(decisions, &(&1.item_id == "item2-guid"))
      assert item2_decision.should_include == false
      assert item2_decision.reasoning == "Test reasoning for item 2"
      assert item2_decision.filtered_feed_id == filtered_feed.id
    end

    test "second evaluation uses cached decisions without calling filter", %{filtered_feed: filtered_feed, rss_content: rss_content, prompt: prompt} do
      # Pre-populate cache with decisions
      {:ok, _} = 
        %FeedItemDecisionSchema{}
        |> FeedItemDecisionSchema.changeset(%{
          item_id: "item1-guid",
          should_include: true,
          reasoning: "Cached decision 1",
          filtered_feed_id: filtered_feed.id
        })
        |> Repo.insert()

      {:ok, _} = 
        %FeedItemDecisionSchema{}
        |> FeedItemDecisionSchema.changeset(%{
          item_id: "item2-guid",
          should_include: false,
          reasoning: "Cached decision 2", 
          filtered_feed_id: filtered_feed.id
        })
        |> Repo.insert()

      # Mock should NOT be called since we have cached decisions
      MockFilter
      |> expect(:should_include?, 0, fn _, _ -> 
        flunk("Filter should not be called when decisions are cached")
      end)

      # Second call should use cache
      {:ok, filtered_xml} = FeedFilter.filter_feed(rss_content, prompt, filtered_feed.id)

      # Verify that only the included item (item1) appears in filtered feed
      assert filtered_xml =~ "Test Item 1"
      refute filtered_xml =~ "Test Item 2"
      assert filtered_xml =~ "Test Item 3"  # No generated_id, included by default
    end

    test "items without generated_id are included without evaluation or caching", %{filtered_feed: filtered_feed, prompt: prompt} do
      # RSS with item that cannot generate ID (no guid, link, or title)
      rss_no_id = """
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <description>Test Description</description>
          <link>https://example.com</link>
          <item>
            <description>Item with no identifiable content</description>
          </item>
        </channel>
      </rss>
      """

      # Mock should NOT be called for items without generated_id
      MockFilter
      |> expect(:should_include?, 0, fn _, _ ->
        flunk("Filter should not be called for items without generated_id")
      end)

      {:ok, filtered_xml} = FeedFilter.filter_feed(rss_no_id, prompt, filtered_feed.id)

      # Item should be included in output
      assert filtered_xml =~ "Item with no identifiable content"

      # No decisions should be stored in database
      decisions = Repo.all(FeedItemDecisionSchema)
      assert length(decisions) == 0
    end

    test "decisions are cached separately per filtered_feed_id", %{rss_content: rss_content, prompt: prompt} do
      # Create user for feeds
      user = user_fixture()
      
      # Create two different filtered feeds
      {:ok, feed1} = 
        %FilteredFeed{}
        |> FilteredFeed.changeset(%{
          url: "https://example.com/feed1.xml",
          prompt: "filter prompt 1",
          user_id: user.id
        })
        |> Repo.insert()

      {:ok, feed2} = 
        %FilteredFeed{}
        |> FilteredFeed.changeset(%{
          url: "https://example.com/feed2.xml", 
          prompt: "filter prompt 2",
          user_id: user.id
        })
        |> Repo.insert()

      # Setup different mock responses for each feed - 3 items per feed = 6 total calls
      MockFilter
      |> expect(:should_include?, 6, fn item, ^prompt ->
        decision = case item.generated_id do
          "item1-guid" -> %FeedItemDecision{item_id: "item1-guid", should_include: true, reasoning: "Feed specific decision"}
          "item2-guid" -> %FeedItemDecision{item_id: "item2-guid", should_include: false, reasoning: "Feed specific decision"}
          generated_id when is_binary(generated_id) -> %FeedItemDecision{item_id: generated_id, should_include: true, reasoning: "Feed specific decision"}
        end
        {:ok, decision}
      end)

      # Process both feeds
      {:ok, _} = FeedFilter.filter_feed(rss_content, prompt, feed1.id)
      {:ok, _} = FeedFilter.filter_feed(rss_content, prompt, feed2.id)

      # Verify separate decisions are stored for each feed
      feed1_decisions = Repo.all(from d in FeedItemDecisionSchema, where: d.filtered_feed_id == ^feed1.id)
      feed2_decisions = Repo.all(from d in FeedItemDecisionSchema, where: d.filtered_feed_id == ^feed2.id)

      assert length(feed1_decisions) == 3
      assert length(feed2_decisions) == 3

      # Verify decisions belong to correct feeds
      Enum.each(feed1_decisions, fn decision -> 
        assert decision.filtered_feed_id == feed1.id
      end)

      Enum.each(feed2_decisions, fn decision ->
        assert decision.filtered_feed_id == feed2.id 
      end)
    end

    test "partial cache hits work correctly", %{filtered_feed: filtered_feed, rss_content: rss_content, prompt: prompt} do
      # Pre-populate cache with decision for only one item
      {:ok, _} = 
        %FeedItemDecisionSchema{}
        |> FeedItemDecisionSchema.changeset(%{
          item_id: "item1-guid",
          should_include: true,
          reasoning: "Cached decision",
          filtered_feed_id: filtered_feed.id
        })
        |> Repo.insert()

      # Mock should only be called for the uncached item
      MockFilter
      |> expect(:should_include?, fn %FeedItem{generated_id: "item2-guid"}, ^prompt ->
        {:ok, %FeedItemDecision{
          item_id: "item2-guid",
          should_include: false,
          reasoning: "New decision"
        }}
      end)

      {:ok, filtered_xml} = FeedFilter.filter_feed(rss_content, prompt, filtered_feed.id)

      # Verify results
      assert filtered_xml =~ "Test Item 1"  # Cached as included
      refute filtered_xml =~ "Test Item 2"  # New decision as excluded
      assert filtered_xml =~ "Test Item 3"  # No ID, included by default

      # Verify only one new decision was stored
      decisions = Repo.all(FeedItemDecisionSchema)
      assert length(decisions) == 2
    end

    test "filter errors result in items being included by default", %{filtered_feed: filtered_feed, rss_content: rss_content, prompt: prompt} do
      # Mock filter that raises an error
      MockFilter
      |> expect(:should_include?, 2, fn _, _ ->
        raise "Simulated filter error"
      end)

      {:ok, filtered_xml} = FeedFilter.filter_feed(rss_content, prompt, filtered_feed.id)

      # All items should be included due to error handling
      assert filtered_xml =~ "Test Item 1"
      assert filtered_xml =~ "Test Item 2" 
      assert filtered_xml =~ "Test Item 3"

      # No decisions should be cached when errors occur
      decisions = Repo.all(FeedItemDecisionSchema)
      assert length(decisions) == 0
    end

    test "fallback decisions are not cached", %{filtered_feed: filtered_feed, rss_content: rss_content, prompt: prompt} do
      # Mock filter that returns error tuples (simulating API failures)
      MockFilter
      |> expect(:should_include?, 4, fn item, ^prompt ->
        fallback_decision = %FeedItemDecision{
          item_id: item.generated_id,
          should_include: true,
          reasoning: "API failed, fallback decision"
        }
        {:error, fallback_decision}
      end)

      # First call - should get fallback decisions, not cache them
      {:ok, filtered_xml1} = FeedFilter.filter_feed(rss_content, prompt, filtered_feed.id)

      # All items should be included (fallback behavior)
      assert filtered_xml1 =~ "Test Item 1"
      assert filtered_xml1 =~ "Test Item 2"
      assert filtered_xml1 =~ "Test Item 3"

      # No decisions should be cached
      decisions = Repo.all(FeedItemDecisionSchema)
      assert length(decisions) == 0

      # Second call - should call filter again since nothing was cached
      {:ok, filtered_xml2} = FeedFilter.filter_feed(rss_content, prompt, filtered_feed.id)

      # Results should be consistent
      assert filtered_xml2 =~ "Test Item 1"
      assert filtered_xml2 =~ "Test Item 2"
      assert filtered_xml2 =~ "Test Item 3"

      # Still no cached decisions
      decisions = Repo.all(FeedItemDecisionSchema)
      assert length(decisions) == 0
    end

    test "database storage errors don't prevent filtering", %{filtered_feed: filtered_feed, rss_content: rss_content, prompt: prompt} do
      # Delete the filtered feed to cause foreign key constraint errors
      Repo.delete!(filtered_feed)

      MockFilter
      |> expect(:should_include?, 2, fn item, ^prompt ->
        {:ok, %FeedItemDecision{
          item_id: item.generated_id,
          should_include: true,
          reasoning: "Should work despite storage error"
        }}
      end)

      # Filtering should still work even if decisions can't be stored
      {:ok, filtered_xml} = FeedFilter.filter_feed(rss_content, prompt, filtered_feed.id)

      assert filtered_xml =~ "Test Item 1"
      assert filtered_xml =~ "Test Item 2"
      assert filtered_xml =~ "Test Item 3"
    end
  end

  describe "mock call verification" do
    test "verifies exact number of filter calls for cache behavior", %{filtered_feed: filtered_feed, rss_content: rss_content, prompt: prompt} do
      # First call - should hit filter for both items with generated_id
      MockFilter
      |> expect(:should_include?, 2, fn item, ^prompt ->
        {:ok, %FeedItemDecision{
          item_id: item.generated_id,
          should_include: true,
          reasoning: "First call decision"
        }}
      end)

      {:ok, _} = FeedFilter.filter_feed(rss_content, prompt, filtered_feed.id)

      # Second call - should not hit filter at all (cached)
      MockFilter
      |> expect(:should_include?, 0, fn _, _ ->
        flunk("Should not call filter on second invocation")
      end)

      {:ok, _} = FeedFilter.filter_feed(rss_content, prompt, filtered_feed.id)

      # Mox will automatically verify that exactly 2 calls were made in total
    end
  end
end