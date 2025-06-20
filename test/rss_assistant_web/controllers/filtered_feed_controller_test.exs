defmodule RssAssistantWeb.FilteredFeedControllerTest do
  use RssAssistantWeb.ConnCase

  alias RssAssistant.FilteredFeed
  alias RssAssistant.Repo

  describe "GET /filtered_feeds/new" do
    test "renders new filtered feed form", %{conn: conn} do
      conn = get(conn, ~p"/filtered_feeds/new")
      assert html_response(conn, 200) =~ "Create Filtered RSS Feed"
      assert html_response(conn, 200) =~ "RSS Feed URL"
      assert html_response(conn, 200) =~ "Filter Description"
    end
  end

  describe "POST /filtered_feeds" do
    test "creates filtered feed with valid data and redirects", %{conn: conn} do
      valid_attrs = %{
        url: "https://example.com/feed.xml",
        prompt: "Filter out sports content"
      }

      conn = post(conn, ~p"/filtered_feeds", filtered_feed: valid_attrs)

      assert %{slug: slug} = redirected_params(conn)
      assert redirected_to(conn) == ~p"/filtered_feeds/#{slug}"

      filtered_feed = Repo.get_by(FilteredFeed, slug: slug)
      assert filtered_feed.url == "https://example.com/feed.xml"
      assert filtered_feed.prompt == "Filter out sports content"
    end

    test "renders errors with invalid data", %{conn: conn} do
      invalid_attrs = %{url: "not-a-url", prompt: ""}

      conn = post(conn, ~p"/filtered_feeds", filtered_feed: invalid_attrs)

      assert html_response(conn, 200) =~ "Create Filtered RSS Feed"
      assert html_response(conn, 200) =~ "must be a valid URL"
      assert html_response(conn, 200) =~ "can&#39;t be blank"
    end
  end

  describe "GET /filtered_feeds/:slug" do
    test "shows filtered feed management page", %{conn: conn} do
      filtered_feed = create_filtered_feed()

      conn = get(conn, ~p"/filtered_feeds/#{filtered_feed.slug}")

      assert html_response(conn, 200) =~ "Manage Filtered RSS Feed"
      assert html_response(conn, 200) =~ filtered_feed.url
      assert html_response(conn, 200) =~ filtered_feed.prompt
      assert html_response(conn, 200) =~ "/filtered_feeds/#{filtered_feed.slug}/rss"
    end

    test "returns 404 for non-existent slug", %{conn: conn} do
      assert_error_sent 404, fn ->
        get(conn, ~p"/filtered_feeds/nonexistent")
      end
    end
  end

  describe "GET /filtered_feeds/:slug/rss" do
    test "serves RSS feed when original feed is accessible", %{conn: conn} do
      # Create a filtered feed pointing to NY Times RSS feed
      filtered_feed =
        create_filtered_feed(%{
          url: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml",
          prompt: "Filter out sports content"
        })

      conn = get(conn, ~p"/filtered_feeds/#{filtered_feed.slug}/rss")

      assert response_content_type(conn, :xml)
      assert conn.status == 200
    end

    test "returns error when original feed is not accessible", %{conn: conn} do
      filtered_feed =
        create_filtered_feed(%{
          url: "https://example.com/nonexistent-feed.xml",
          prompt: "Filter out sports content"
        })

      conn = get(conn, ~p"/filtered_feeds/#{filtered_feed.slug}/rss")

      assert conn.status == 502
      assert response(conn, 502) =~ "Error fetching RSS feed"
    end

    test "returns 404 for non-existent slug", %{conn: conn} do
      assert_error_sent 404, fn ->
        get(conn, ~p"/filtered_feeds/nonexistent/rss")
      end
    end
  end

  describe "PATCH /filtered_feeds/:slug" do
    test "updates filtered feed with valid data", %{conn: conn} do
      filtered_feed = create_filtered_feed()

      update_attrs = %{
        url: "https://updated.com/feed.xml",
        prompt: "Updated filter description"
      }

      conn = patch(conn, ~p"/filtered_feeds/#{filtered_feed.slug}", filtered_feed: update_attrs)

      assert redirected_to(conn) == ~p"/filtered_feeds/#{filtered_feed.slug}"

      updated_feed = Repo.get!(FilteredFeed, filtered_feed.id)
      assert updated_feed.url == "https://updated.com/feed.xml"
      assert updated_feed.prompt == "Updated filter description"
    end

    test "renders errors with invalid data", %{conn: conn} do
      filtered_feed = create_filtered_feed()

      invalid_attrs = %{url: "not-a-url", prompt: ""}

      conn = patch(conn, ~p"/filtered_feeds/#{filtered_feed.slug}", filtered_feed: invalid_attrs)

      assert html_response(conn, 200) =~ "Manage Filtered RSS Feed"
      assert html_response(conn, 200) =~ "must be a valid URL"
      assert html_response(conn, 200) =~ "can&#39;t be blank"
    end
  end

  defp create_filtered_feed(attrs \\ %{}) do
    default_attrs = %{
      url: "https://example.com/feed.xml",
      prompt: "Filter out sports content"
    }

    %FilteredFeed{}
    |> FilteredFeed.changeset(Map.merge(default_attrs, attrs))
    |> Repo.insert!()
  end
end
