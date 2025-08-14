defmodule RssAssistantWeb.PageController do
  use RssAssistantWeb, :controller

  alias RssAssistant.Accounts

  def home(conn, _params) do
    if user = conn.assigns[:current_user] do
      plan = Accounts.get_user_plan(user)
      feed_count = Accounts.get_user_feed_count(user)
      user_feeds = Accounts.get_user_feeds(user)
      feed_status = Accounts.can_create_feed?(user)

      render(conn, :home,
        layout: false,
        user: user,
        plan: plan,
        feed_count: feed_count,
        user_feeds: user_feeds,
        can_create_feed: feed_status.can_create
      )
    else
      render(conn, :home, layout: false)
    end
  end
end
