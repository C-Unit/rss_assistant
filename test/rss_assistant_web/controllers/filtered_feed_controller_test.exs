defmodule RssAssistantWeb.FilteredFeedControllerTest do
  use RssAssistantWeb.ConnCase

  import RssAssistant.AccountsFixtures
  import RssAssistant.FilteredFeedFixtures

  alias RssAssistant.{Accounts, FilteredFeed, Repo}

  setup do
    free_plan_fixture()
    pro_plan_fixture()
    %{}
  end

  describe "GET /filtered_feeds/new - unauthenticated" do
    test "redirects to login page", %{conn: conn} do
      conn = get(conn, ~p"/filtered_feeds/new")
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "GET /filtered_feeds/new - authenticated" do
    test "renders new form for user with available feeds", %{conn: conn} do
      user = user_fixture()
      Accounts.change_user_plan(user, "Pro")

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/filtered_feeds/new")

      assert html_response(conn, 200) =~ "Create Filtered RSS Feed"
    end

    test "redirects to home when user has reached plan limit", %{conn: conn} do
      # Free plan (0 feeds)
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/filtered_feeds/new")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "reached your plan limit"
    end
  end

  describe "POST /filtered_feeds - unauthenticated" do
    test "redirects to login page", %{conn: conn} do
      conn = post(conn, ~p"/filtered_feeds", filtered_feed: %{})
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "POST /filtered_feeds - authenticated" do
    test "creates filtered feed with valid data for pro user", %{conn: conn} do
      user = user_fixture()
      Accounts.change_user_plan(user, "Pro")

      valid_attrs = %{
        url: "https://example.com/feed.xml",
        prompt: "Filter out sports content"
      }

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/filtered_feeds", filtered_feed: valid_attrs)

      assert %{slug: slug} = redirected_params(conn)
      assert redirected_to(conn) == ~p"/filtered_feeds/#{slug}"

      filtered_feed = Repo.get_by(FilteredFeed, slug: slug)
      assert filtered_feed.url == "https://example.com/feed.xml"
      assert filtered_feed.prompt == "Filter out sports content"
      assert filtered_feed.user_id == user.id
    end

    test "redirects to home when user has reached plan limit", %{conn: conn} do
      # Free plan (0 feeds)
      user = user_fixture()

      valid_attrs = %{
        url: "https://example.com/feed.xml",
        prompt: "Filter out sports content"
      }

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/filtered_feeds", filtered_feed: valid_attrs)

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "reached your plan limit"
    end

    test "renders errors with invalid data", %{conn: conn} do
      user = user_fixture()
      Accounts.change_user_plan(user, "Pro")

      invalid_attrs = %{url: "not-a-url", prompt: ""}

      conn =
        conn
        |> log_in_user(user)
        |> post(~p"/filtered_feeds", filtered_feed: invalid_attrs)

      assert html_response(conn, 200) =~ "Create Filtered RSS Feed"
    end
  end

  describe "GET /filtered_feeds/:slug - unauthenticated" do
    test "redirects to login page", %{conn: conn} do
      user = user_fixture()
      feed = filtered_feed_fixture(%{user_id: user.id})

      conn = get(conn, ~p"/filtered_feeds/#{feed.slug}")
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "GET /filtered_feeds/:slug - authenticated" do
    test "shows filtered feed for owner", %{conn: conn} do
      user = user_fixture()
      feed = filtered_feed_fixture(%{user_id: user.id})

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/filtered_feeds/#{feed.slug}")

      assert html_response(conn, 200) =~ feed.url
      assert html_response(conn, 200) =~ feed.prompt
    end

    test "returns 404 when accessing another user's feed", %{conn: conn} do
      owner = user_fixture()
      other_user = user_fixture()
      feed = filtered_feed_fixture(%{user_id: owner.id})

      assert_error_sent 404, fn ->
        conn
        |> log_in_user(other_user)
        |> get(~p"/filtered_feeds/#{feed.slug}")
      end
    end

    test "returns 404 for non-existent slug", %{conn: conn} do
      user = user_fixture()

      assert_error_sent 404, fn ->
        conn
        |> log_in_user(user)
        |> get(~p"/filtered_feeds/nonexistent")
      end
    end
  end

  describe "PATCH /filtered_feeds/:slug - unauthenticated" do
    test "redirects to login page", %{conn: conn} do
      user = user_fixture()
      feed = filtered_feed_fixture(%{user_id: user.id})

      conn = patch(conn, ~p"/filtered_feeds/#{feed.slug}", filtered_feed: %{})
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "PATCH /filtered_feeds/:slug - authenticated" do
    test "updates filtered feed for owner", %{conn: conn} do
      user = user_fixture()
      feed = filtered_feed_fixture(%{user_id: user.id})

      update_attrs = %{
        url: "https://updated.com/feed.xml",
        prompt: "Updated filter description"
      }

      conn =
        conn
        |> log_in_user(user)
        |> patch(~p"/filtered_feeds/#{feed.slug}", filtered_feed: update_attrs)

      assert redirected_to(conn) == ~p"/filtered_feeds/#{feed.slug}"

      updated_feed = Repo.get!(FilteredFeed, feed.id)
      assert updated_feed.url == "https://updated.com/feed.xml"
      assert updated_feed.prompt == "Updated filter description"
    end

    test "returns 404 when updating another user's feed", %{conn: conn} do
      owner = user_fixture()
      other_user = user_fixture()
      feed = filtered_feed_fixture(%{user_id: owner.id})

      assert_error_sent 404, fn ->
        conn
        |> log_in_user(other_user)
        |> patch(~p"/filtered_feeds/#{feed.slug}", filtered_feed: %{prompt: "hacked"})
      end
    end
  end

  describe "GET /filtered_feeds/:slug/rss - public access" do
    test "serves RSS feed for any user's feed", %{conn: conn} do
      user = user_fixture()

      feed =
        filtered_feed_fixture(%{
          user_id: user.id,
          url: "https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml"
        })

      conn = get(conn, ~p"/filtered_feeds/#{feed.slug}/rss")

      assert response_content_type(conn, :xml)
      assert conn.status == 200
    end

    test "returns error when original feed is not accessible", %{conn: conn} do
      user = user_fixture()

      feed =
        filtered_feed_fixture(%{
          user_id: user.id,
          url: "https://example.com/nonexistent-feed.xml"
        })

      conn = get(conn, ~p"/filtered_feeds/#{feed.slug}/rss")

      assert conn.status == 502
      assert response(conn, 502) =~ "Error fetching RSS feed"
    end

    test "returns 404 for non-existent slug", %{conn: conn} do
      assert_error_sent 404, fn ->
        get(conn, ~p"/filtered_feeds/nonexistent/rss")
      end
    end
  end

  describe "plan limits enforcement" do
    test "pro user can create up to 100 feeds", %{conn: conn} do
      user = user_fixture()
      Accounts.change_user_plan(user, "Pro")

      # Create 99 feeds
      for _i <- 1..99 do
        filtered_feed_fixture(%{user_id: user.id})
      end

      # Should still be able to create the 100th
      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/filtered_feeds/new")

      assert html_response(conn, 200) =~ "Create Filtered RSS Feed"

      # Create the 100th feed
      valid_attrs = %{
        url: "https://example.com/feed100.xml",
        prompt: "Feed 100"
      }

      conn =
        conn
        |> post(~p"/filtered_feeds", filtered_feed: valid_attrs)

      assert %{slug: _slug} = redirected_params(conn)

      # Now should be at limit
      conn =
        build_conn()
        |> log_in_user(user)
        |> get(~p"/filtered_feeds/new")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "reached your plan limit"
    end
  end

  describe "DELETE /filtered_feeds/:slug - unauthenticated" do
    test "redirects to login page", %{conn: conn} do
      user = user_fixture()
      feed = filtered_feed_fixture(%{user_id: user.id})

      conn = delete(conn, ~p"/filtered_feeds/#{feed.slug}")
      assert redirected_to(conn) == ~p"/users/log_in"
    end
  end

  describe "DELETE /filtered_feeds/:slug - authenticated" do
    test "deletes filtered feed for owner", %{conn: conn} do
      user = user_fixture()
      feed = filtered_feed_fixture(%{user_id: user.id})

      conn =
        conn
        |> log_in_user(user)
        |> delete(~p"/filtered_feeds/#{feed.slug}")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "deleted successfully"

      # Verify feed is actually deleted
      assert Repo.get(FilteredFeed, feed.id) == nil
    end

    test "deletes associated feed item decisions on cascade", %{conn: conn} do
      user = user_fixture()
      feed = filtered_feed_fixture(%{user_id: user.id})

      # Create a feed item decision
      {:ok, decision} =
        %RssAssistant.FeedItemDecision{}
        |> RssAssistant.FeedItemDecision.changeset(%{
          item_id: "test-item",
          should_include: false,
          reasoning: "Test reason",
          filtered_feed_id: feed.id
        })
        |> Repo.insert()

      conn =
        conn
        |> log_in_user(user)
        |> delete(~p"/filtered_feeds/#{feed.slug}")

      assert redirected_to(conn) == ~p"/"

      # Verify both feed and decision are deleted
      assert Repo.get(FilteredFeed, feed.id) == nil
      assert Repo.get(RssAssistant.FeedItemDecision, decision.id) == nil
    end

    test "returns 404 when deleting another user's feed", %{conn: conn} do
      owner = user_fixture()
      other_user = user_fixture()
      feed = filtered_feed_fixture(%{user_id: owner.id})

      assert_error_sent 404, fn ->
        conn
        |> log_in_user(other_user)
        |> delete(~p"/filtered_feeds/#{feed.slug}")
      end

      # Verify feed still exists
      assert Repo.get(FilteredFeed, feed.id) != nil
    end

    test "returns 404 for non-existent slug", %{conn: conn} do
      user = user_fixture()

      assert_error_sent 404, fn ->
        conn
        |> log_in_user(user)
        |> delete(~p"/filtered_feeds/nonexistent")
      end
    end

    test "decrements user feed count after deletion", %{conn: conn} do
      user = user_fixture()
      Accounts.change_user_plan(user, "Pro")
      feed = filtered_feed_fixture(%{user_id: user.id})

      initial_count = Accounts.get_user_feed_count(user.id)

      conn
      |> log_in_user(user)
      |> delete(~p"/filtered_feeds/#{feed.slug}")

      final_count = Accounts.get_user_feed_count(user.id)
      assert final_count == initial_count - 1
    end
  end

  describe "filtered items display" do
    test "shows excluded items but not included items", %{conn: conn} do
      user = user_fixture()
      feed = filtered_feed_fixture(%{user_id: user.id})

      # Create excluded item
      {:ok, _excluded} =
        %RssAssistant.FeedItemDecision{}
        |> RssAssistant.FeedItemDecision.changeset(%{
          item_id: "excluded",
          should_include: false,
          reasoning: "Contains sports content",
          title: "Sports News",
          description: "Latest sports updates",
          filtered_feed_id: feed.id
        })
        |> Repo.insert()

      # Create included item
      {:ok, _included} =
        %RssAssistant.FeedItemDecision{}
        |> RssAssistant.FeedItemDecision.changeset(%{
          item_id: "included",
          should_include: true,
          reasoning: "Allowed through",
          title: "Tech News",
          description: "Technology updates",
          filtered_feed_id: feed.id
        })
        |> Repo.insert()

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/filtered_feeds/#{feed.slug}")

      response = html_response(conn, 200)
      assert response =~ "Sports News"
      assert response =~ "Contains sports content"
      refute response =~ "Tech News"
    end

    test "limits filtered items to 20", %{conn: conn} do
      user = user_fixture()
      feed = filtered_feed_fixture(%{user_id: user.id})

      # Create 25 filtered items
      for i <- 1..25 do
        {:ok, _item} =
          %RssAssistant.FeedItemDecision{}
          |> RssAssistant.FeedItemDecision.changeset(%{
            item_id: "item#{i}",
            should_include: false,
            reasoning: "Test reason #{i}",
            title: "Title #{i}",
            description: "Description #{i}",
            filtered_feed_id: feed.id
          })
          |> Repo.insert()
      end

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/filtered_feeds/#{feed.slug}")

      # Check that exactly 20 items are displayed
      filtered_items = conn.assigns.filtered_items
      assert length(filtered_items) == 20
    end

    test "shows message when no filtered items exist", %{conn: conn} do
      user = user_fixture()
      feed = filtered_feed_fixture(%{user_id: user.id})

      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/filtered_feeds/#{feed.slug}")

      response = html_response(conn, 200)
      assert response =~ "No items have been filtered out yet"
    end
  end
end
