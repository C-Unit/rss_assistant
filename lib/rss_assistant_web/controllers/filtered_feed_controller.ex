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

  def rss_feed(conn, %{"slug" => slug}) do
    filtered_feed = Repo.get_by!(FilteredFeed, slug: slug)
    
    case fetch_original_feed(filtered_feed.url) do
      {:ok, feed_content, content_type} ->
        conn
        |> put_resp_content_type(content_type)
        |> send_resp(200, feed_content)
      
      {:error, _reason} ->
        conn
        |> put_status(:bad_gateway)
        |> text("Error fetching RSS feed")
    end
  end

  defp fetch_original_feed(url) do
    case Req.get(url) do
      {:ok, %Req.Response{status: 200, body: body, headers: headers}} ->
        content_type = get_content_type(headers)
        {:ok, body, content_type}
      
      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP #{status}"}
      
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_content_type(headers) do
    case Map.get(headers, "content-type") do
      [content_type | _] -> content_type
      content_type when is_binary(content_type) -> content_type
      _ -> "application/rss+xml"
    end
  end
end