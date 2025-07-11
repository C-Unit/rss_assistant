defmodule RssAssistantWeb.FilteredFeedController do
  use RssAssistantWeb, :controller

  alias RssAssistant.Accounts
  alias RssAssistant.FeedFilter
  alias RssAssistant.FeedItemDecision
  alias RssAssistant.FilteredFeed
  alias RssAssistant.Repo
  import Ecto.Query

  def new(conn, _params) do
    user = conn.assigns.current_user
    feed_status = Accounts.can_create_feed?(user)

    if feed_status.can_create do
      changeset = FilteredFeed.changeset(%FilteredFeed{}, %{})
      render(conn, :new, changeset: changeset)
    else
      conn
      |> put_flash(:error, plan_limit_error_message(feed_status))
      |> redirect(to: ~p"/")
    end
  end

  def create(conn, %{"filtered_feed" => filtered_feed_params}) do
    user = conn.assigns.current_user
    feed_status = Accounts.can_create_feed?(user)

    if feed_status.can_create do
      filtered_feed_params = Map.put(filtered_feed_params, "user_id", user.id)
      changeset = FilteredFeed.changeset(%FilteredFeed{}, filtered_feed_params)

      case Repo.insert(changeset) do
        {:ok, filtered_feed} ->
          conn
          |> put_flash(:info, "Filtered feed created successfully!")
          |> redirect(to: ~p"/filtered_feeds/#{filtered_feed.slug}")

        {:error, changeset} ->
          render(conn, :new, changeset: changeset)
      end
    else
      conn
      |> put_flash(:error, plan_limit_error_message(feed_status))
      |> redirect(to: ~p"/")
    end
  end

  def show(conn, %{"slug" => slug}) do
    user = conn.assigns.current_user
    filtered_feed = Accounts.get_user_filtered_feed_by_slug(user, slug)
    changeset = FilteredFeed.changeset(filtered_feed, %{})
    filtered_items = get_filtered_items(filtered_feed.id)

    render(conn, :show,
      filtered_feed: filtered_feed,
      changeset: changeset,
      filtered_items: filtered_items
    )
  end

  def update(conn, %{"slug" => slug, "filtered_feed" => filtered_feed_params}) do
    user = conn.assigns.current_user
    filtered_feed = Accounts.get_user_filtered_feed_by_slug(user, slug)
    changeset = FilteredFeed.changeset(filtered_feed, filtered_feed_params)

    case Repo.update(changeset) do
      {:ok, filtered_feed} ->
        conn
        |> put_flash(:info, "Filtered feed updated successfully!")
        |> redirect(to: ~p"/filtered_feeds/#{filtered_feed.slug}")

      {:error, changeset} ->
        filtered_items = get_filtered_items(filtered_feed.id)

        render(conn, :show,
          filtered_feed: filtered_feed,
          changeset: changeset,
          filtered_items: filtered_items
        )
    end
  end

  def rss_feed(conn, %{"slug" => slug}) do
    filtered_feed = Repo.get_by!(FilteredFeed, slug: slug)

    case fetch_and_filter_feed(filtered_feed) do
      {:ok, filtered_content, content_type} ->
        conn
        |> put_resp_content_type(content_type)
        |> send_resp(200, filtered_content)

      {:error, _reason} ->
        conn
        |> put_status(:bad_gateway)
        |> text("Error fetching RSS feed")
    end
  end

  defp fetch_and_filter_feed(%FilteredFeed{id: id, url: url, prompt: prompt}) do
    case fetch_original_feed(url) do
      {:ok, feed_content, content_type} ->
        case FeedFilter.filter_feed(feed_content, prompt, id) do
          {:ok, filtered_content} ->
            {:ok, filtered_content, content_type}

          {:error, _reason} ->
            # Fallback to original feed if filtering fails
            {:ok, feed_content, content_type}
        end

      error ->
        error
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

  defp get_filtered_items(filtered_feed_id) do
    query =
      from d in FeedItemDecision,
        where: d.filtered_feed_id == ^filtered_feed_id and d.should_include == false,
        order_by: [desc: d.inserted_at],
        limit: 20,
        select: d

    Repo.all(query)
  end

  defp plan_limit_error_message(feed_status) do
    "You have reached your plan limit of #{feed_status.plan.max_feeds} filtered feeds. You currently have #{feed_status.current_count} feeds."
  end
end
