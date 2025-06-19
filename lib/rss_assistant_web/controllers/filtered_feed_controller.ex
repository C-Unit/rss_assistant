defmodule RssAssistantWeb.FilteredFeedController do
  use RssAssistantWeb, :controller

  alias RssAssistant.FilteredFeed
  alias RssAssistant.Repo

  def new(conn, _params) do
    changeset = FilteredFeed.changeset(%FilteredFeed{}, %{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"filtered_feed" => filtered_feed_params}) do
    changeset = FilteredFeed.changeset(%FilteredFeed{}, filtered_feed_params)

    case Repo.insert(changeset) do
      {:ok, filtered_feed} ->
        conn
        |> put_flash(:info, "Filtered feed created successfully!")
        |> redirect(to: ~p"/filtered_feeds/#{filtered_feed.slug}")

      {:error, changeset} ->
        render(conn, :new, changeset: changeset)
    end
  end

  def show(conn, %{"slug" => slug}) do
    filtered_feed = Repo.get_by!(FilteredFeed, slug: slug)
    changeset = FilteredFeed.changeset(filtered_feed, %{})
    render(conn, :show, filtered_feed: filtered_feed, changeset: changeset)
  end

  def update(conn, %{"slug" => slug, "filtered_feed" => filtered_feed_params}) do
    filtered_feed = Repo.get_by!(FilteredFeed, slug: slug)
    changeset = FilteredFeed.changeset(filtered_feed, filtered_feed_params)

    case Repo.update(changeset) do
      {:ok, filtered_feed} ->
        conn
        |> put_flash(:info, "Filtered feed updated successfully!")
        |> redirect(to: ~p"/filtered_feeds/#{filtered_feed.slug}")

      {:error, changeset} ->
        render(conn, :show, filtered_feed: filtered_feed, changeset: changeset)
    end
  end
end