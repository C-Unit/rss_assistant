defmodule RssAssistantWeb.PageControllerTest do
  use RssAssistantWeb.ConnCase

  import RssAssistant.AccountsFixtures
  import RssAssistant.FilteredFeedFixtures

  alias RssAssistant.Accounts

  setup do
    free_plan_fixture()
    pro_plan_fixture()
    %{}
  end

  test "GET / when not logged in", %{conn: conn} do
    conn = get(conn, ~p"/")
    response = html_response(conn, 200)
    
    assert response =~ "RSS Assistant"
    assert response =~ "Sign Up"
    assert response =~ "Log In"
    refute response =~ "Your Dashboard"
  end

  test "GET / when logged in with free plan", %{conn: conn} do
    user = user_fixture()
    
    conn = 
      conn
      |> log_in_user(user)
      |> get(~p"/")
    
    response = html_response(conn, 200)
    
    assert response =~ "RSS Assistant"
    assert response =~ "Your Dashboard"
    assert response =~ "Free"
    assert response =~ "0 / 0"
    assert response =~ "Limit Reached"
    assert response =~ "reached your plan limit"
    refute response =~ "Create New Filtered Feed"
  end

  test "GET / when logged in with pro plan and no feeds", %{conn: conn} do
    user = user_fixture()
    Accounts.change_user_plan(user, "Pro")
    
    conn = 
      conn
      |> log_in_user(user)
      |> get(~p"/")
    
    response = html_response(conn, 200)
    
    assert response =~ "Your Dashboard"
    assert response =~ "Pro"
    assert response =~ "0 / 100"
    assert response =~ "Can Create"
    assert response =~ "Create New Filtered Feed"
    refute response =~ "reached your plan limit"
  end

  test "GET / when logged in with pro plan and feeds", %{conn: conn} do
    user = user_fixture()
    Accounts.change_user_plan(user, "Pro")
    
    feed1 = filtered_feed_fixture(%{
      user_id: user.id,
      url: "https://example.com/feed1.xml",
      prompt: "Filter sports"
    })
    
    feed2 = filtered_feed_fixture(%{
      user_id: user.id,
      url: "https://example.com/feed2.xml",
      prompt: "Filter politics"
    })
    
    conn = 
      conn
      |> log_in_user(user)
      |> get(~p"/")
    
    response = html_response(conn, 200)
    
    assert response =~ "Your Dashboard"
    assert response =~ "2 / 100"
    assert response =~ "Can Create"
    assert response =~ "Your Filtered Feeds"
    assert response =~ "feed1.xml"
    assert response =~ "feed2.xml"
    assert response =~ "Filter sports"
    assert response =~ "Filter politics"
    assert response =~ "/filtered_feeds/#{feed1.slug}"
    assert response =~ "/filtered_feeds/#{feed2.slug}/rss"
  end

  test "GET / when logged in with pro plan at limit", %{conn: conn} do
    user = user_fixture()
    Accounts.change_user_plan(user, "Pro")
    
    # Create 100 feeds (at limit)
    for i <- 1..100 do
      filtered_feed_fixture(%{
        user_id: user.id,
        url: "https://example.com/feed#{i}.xml",
        prompt: "Filter #{i}"
      })
    end
    
    conn = 
      conn
      |> log_in_user(user)
      |> get(~p"/")
    
    response = html_response(conn, 200)
    
    assert response =~ "100 / 100"
    assert response =~ "Limit Reached"
    assert response =~ "reached your plan limit"
    refute response =~ "Create New Filtered Feed"
  end

  test "dashboard shows feeds ordered by most recent", %{conn: conn} do
    user = user_fixture()
    Accounts.change_user_plan(user, "Pro")
    
    # Create feeds with explicit timestamps to ensure ordering
    older_time = ~U[2023-01-01 10:00:00Z]
    newer_time = ~U[2023-01-01 11:00:00Z]
    
    _feed1 = %RssAssistant.FilteredFeed{}
    |> RssAssistant.FilteredFeed.changeset(%{
      user_id: user.id,
      url: "https://example.com/old-feed.xml",
      prompt: "Old feed"
    })
    |> Ecto.Changeset.put_change(:inserted_at, older_time)
    |> RssAssistant.Repo.insert!()
    
    _feed2 = %RssAssistant.FilteredFeed{}
    |> RssAssistant.FilteredFeed.changeset(%{
      user_id: user.id,
      url: "https://example.com/new-feed.xml", 
      prompt: "New feed"
    })
    |> Ecto.Changeset.put_change(:inserted_at, newer_time)
    |> RssAssistant.Repo.insert!()
    
    conn = 
      conn
      |> log_in_user(user)
      |> get(~p"/")
    
    response = html_response(conn, 200)
    
    # Check that the newer feed appears before the older one in the HTML
    case :binary.match(response, "new-feed.xml") do
      {new_feed_pos, _} ->
        case :binary.match(response, "old-feed.xml") do
          {old_feed_pos, _} ->
            assert new_feed_pos < old_feed_pos
          :nomatch ->
            flunk("Could not find old-feed.xml in response")
        end
      :nomatch ->
        flunk("Could not find new-feed.xml in response")
    end
  end
end
