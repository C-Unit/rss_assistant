defmodule RssAssistant.FeedFilter do
  @moduledoc """
  Filters RSS feed content based on user prompts using configurable filter implementations.

  This module coordinates between parsing the original feed, filtering items,
  and reconstructing a valid RSS/Atom feed with only the included items.
  """

  import SweetXml
  import Ecto.Query
  alias RssAssistant.{FeedParser, FeedItem, FeedItemDecision, FeedItemDecisionSchema, Repo}

  @doc """
  Filters an RSS feed based on a user prompt.

  ## Parameters

    * `xml_content` - The original RSS/Atom feed XML content
    * `prompt` - The user's filtering prompt
    * `filtered_feed_id` - The ID of the filtered feed for caching decisions

  ## Returns

    * `{:ok, filtered_xml}` - Successfully filtered feed
    * `{:error, reason}` - Error occurred, original feed should be returned
  """
  @spec filter_feed(String.t(), String.t(), integer()) :: {:ok, String.t()} | {:error, term()}
  def filter_feed(xml_content, prompt, filtered_feed_id) when is_binary(xml_content) and is_binary(prompt) and is_integer(filtered_feed_id) do
    with {:ok, items} <- FeedParser.parse_feed(xml_content),
         filtered_items <- filter_items(items, prompt, filtered_feed_id),
         {:ok, filtered_xml} <- rebuild_feed(xml_content, filtered_items) do
      {:ok, filtered_xml}
    else
      error -> error
    end
  end

  def filter_feed(_, _, _), do: {:error, :invalid_input}

  # Filter items using the configured filter implementation with caching
  defp filter_items(items, prompt, filtered_feed_id) do
    filter_impl =
      Application.get_env(:rss_assistant, :filter_impl, RssAssistant.Filter.AlwaysInclude)

    Enum.filter(items, fn item ->
      try do
        case get_or_create_decision(item, prompt, filtered_feed_id, filter_impl) do
          %FeedItemDecision{should_include: should_include} -> should_include
          _ -> true  # Default to include if decision struct is invalid
        end
      rescue
        # Include item if filtering fails
        _error -> true
      end
    end)
  end

  # Get cached decision or create new one
  defp get_or_create_decision(%FeedItem{generated_id: nil}, _prompt, _filtered_feed_id, _filter_impl) do
    # No generated_id, include by default without evaluation or caching
    %FeedItemDecision{should_include: true, reasoning: "No generated_id, included by default"}
  end


  defp get_or_create_decision(%FeedItem{generated_id: item_id} = item, prompt, filtered_feed_id, filter_impl) do
    case get_cached_decision(item_id, filtered_feed_id) do
      nil ->
        # No cached decision, call filter and store result
        decision = filter_impl.should_include?(item, prompt)
        store_decision(decision, filtered_feed_id)
        decision

      cached_decision ->
        # Return cached decision
        cached_decision
    end
  end

  # Retrieve cached decision from database
  defp get_cached_decision(item_id, filtered_feed_id) do
    query = from d in FeedItemDecisionSchema,
      where: d.item_id == ^item_id and d.filtered_feed_id == ^filtered_feed_id,
      select: d

    case Repo.one(query) do
      nil -> nil
      decision_schema ->
        %FeedItemDecision{
          item_id: decision_schema.item_id,
          should_include: decision_schema.should_include,
          reasoning: decision_schema.reasoning,
          timestamp: decision_schema.inserted_at
        }
    end
  end

  # Store decision in database
  defp store_decision(%FeedItemDecision{} = decision, filtered_feed_id) do
    changeset = FeedItemDecisionSchema.changeset(%FeedItemDecisionSchema{}, %{
      item_id: decision.item_id,
      should_include: decision.should_include,
      reasoning: decision.reasoning,
      filtered_feed_id: filtered_feed_id
    })

    case Repo.insert(changeset) do
      {:ok, _} -> :ok
      {:error, _} -> :error  # Ignore storage errors, don't fail the filtering
    end
  end

  # Rebuild the RSS/Atom feed with only the filtered items
  defp rebuild_feed(original_xml, filtered_items) do
    try do
      parsed_xml = parse(original_xml)

      # Determine if this is RSS or Atom format
      if xpath(parsed_xml, ~x"//rss") do
        rebuild_rss_feed(parsed_xml, filtered_items)
      else
        rebuild_atom_feed(parsed_xml, filtered_items)
      end
    rescue
      _error -> {:error, :rebuild_failed}
    catch
      :exit, _reason -> {:error, :rebuild_failed}
    end
  end

  # Rebuild RSS 2.0 format feed
  defp rebuild_rss_feed(parsed_xml, filtered_items) do
    # Extract channel metadata
    channel_info =
      xpath(
        parsed_xml,
        ~x"//channel",
        title: ~x"./title/text()"s,
        description: ~x"./description/text()"s,
        link: ~x"./link/text()"s,
        language: ~x"./language/text()"s,
        last_build_date: ~x"./lastBuildDate/text()"s,
        pub_date: ~x"./pubDate/text()"s,
        copyright: ~x"./copyright/text()"s
      )

    # Build new RSS XML
    rss_xml = build_rss_xml(channel_info, filtered_items)
    {:ok, rss_xml}
  end

  # Rebuild Atom format feed
  defp rebuild_atom_feed(parsed_xml, filtered_items) do
    # Extract feed metadata
    feed_info =
      xpath(
        parsed_xml,
        ~x"//feed",
        title: ~x"./title/text()"s,
        subtitle: ~x"./subtitle/text()"s,
        link: ~x"./link[@rel='alternate']/@href"s,
        id: ~x"./id/text()"s,
        updated: ~x"./updated/text()"s
      )

    # Build new Atom XML
    atom_xml = build_atom_xml(feed_info, filtered_items)
    {:ok, atom_xml}
  end

  # Build RSS XML structure
  defp build_rss_xml(channel_info, items) do
    items_xml =
      items
      |> Enum.map(&build_rss_item_xml/1)
      |> Enum.join("\n")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0">
      <channel>
        <title>#{escape_xml(channel_info[:title] || "")}</title>
        <description>#{escape_xml(channel_info[:description] || "")}</description>
        <link>#{escape_xml(channel_info[:link] || "")}</link>
        #{if channel_info[:language], do: "<language>#{escape_xml(channel_info[:language])}</language>", else: ""}
        #{if channel_info[:copyright], do: "<copyright>#{escape_xml(channel_info[:copyright])}</copyright>", else: ""}
        #{if channel_info[:last_build_date], do: "<lastBuildDate>#{escape_xml(channel_info[:last_build_date])}</lastBuildDate>", else: ""}
        #{if channel_info[:pub_date], do: "<pubDate>#{escape_xml(channel_info[:pub_date])}</pubDate>", else: ""}
        #{items_xml}
      </channel>
    </rss>
    """
  end

  # Build Atom XML structure
  defp build_atom_xml(feed_info, items) do
    entries_xml =
      items
      |> Enum.map(&build_atom_entry_xml/1)
      |> Enum.join("\n")

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <feed xmlns="http://www.w3.org/2005/Atom">
      <title>#{escape_xml(feed_info[:title] || "")}</title>
      #{if feed_info[:subtitle], do: "<subtitle>#{escape_xml(feed_info[:subtitle])}</subtitle>", else: ""}
      <link href="#{escape_xml(feed_info[:link] || "")}" rel="alternate"/>
      <id>#{escape_xml(feed_info[:id] || "")}</id>
      #{if feed_info[:updated], do: "<updated>#{escape_xml(feed_info[:updated])}</updated>", else: ""}
      #{entries_xml}
    </feed>
    """
  end

  # Build individual RSS item XML
  defp build_rss_item_xml(%FeedItem{} = item) do
    categories_xml =
      item.categories
      |> Enum.map(fn cat -> "<category>#{escape_xml(cat)}</category>" end)
      |> Enum.join("\n")

    """
        <item>
          #{if item.title, do: "<title>#{escape_xml(item.title)}</title>", else: ""}
          #{if item.description, do: "<description><![CDATA[#{item.description}]]></description>", else: ""}
          #{if item.link, do: "<link>#{escape_xml(item.link)}</link>", else: ""}
          #{if item.pub_date, do: "<pubDate>#{escape_xml(item.pub_date)}</pubDate>", else: ""}
          #{if item.guid, do: "<guid>#{escape_xml(item.guid)}</guid>", else: ""}
          #{categories_xml}
        </item>
    """
  end

  # Build individual Atom entry XML
  defp build_atom_entry_xml(%FeedItem{} = item) do
    """
        <entry>
          #{if item.title, do: "<title>#{escape_xml(item.title)}</title>", else: ""}
          #{if item.description, do: "<summary><![CDATA[#{item.description}]]></summary>", else: ""}
          #{if item.link, do: "<link href=\"#{escape_xml(item.link)}\" rel=\"alternate\"/>", else: ""}
          #{if item.pub_date, do: "<published>#{escape_xml(item.pub_date)}</published>", else: ""}
          #{if item.guid, do: "<id>#{escape_xml(item.guid)}</id>", else: ""}
        </entry>
    """
  end

  # Escape XML special characters
  defp escape_xml(nil), do: ""

  defp escape_xml(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end
end
