defmodule RssAssistant.FeedParser do
  @moduledoc """
  Parses RSS and Atom feeds into structured RssItem data.

  Supports both RSS 2.0 and Atom feed formats using SweetXml for parsing.
  """

  import SweetXml
  alias RssAssistant.RssItem

  @doc """
  Parses an RSS or Atom feed XML string into a list of RssItem structs.

  ## Examples

      iex> xml = "<rss><channel><item><title>Test</title></item></channel></rss>"
      iex> RssAssistant.FeedParser.parse_feed(xml)
      {:ok, [%RssItem{title: "Test", ...}]}
      
      iex> RssAssistant.FeedParser.parse_feed("invalid xml")
      {:error, :invalid_xml}
  """
  @spec parse_feed(String.t()) :: {:ok, [RssItem.t()]} | {:error, :invalid_xml}
  def parse_feed(xml_string) when is_binary(xml_string) do
    try do
      parsed_xml = parse(xml_string)

      # Try RSS format first, then Atom
      items = parse_rss_items(parsed_xml) || parse_atom_entries(parsed_xml) || []

      {:ok, items}
    rescue
      _error -> {:error, :invalid_xml}
    catch
      :exit, _reason -> {:error, :invalid_xml}
    end
  end

  def parse_feed(_), do: {:error, :invalid_xml}

  # Parse RSS 2.0 format items
  defp parse_rss_items(xml) do
    xml
    |> xpath(
      ~x"//item"le,
      title: ~x"./title/text()"s,
      description: ~x"./description/text()"s,
      content: ~x"./content:encoded/text()"s,
      link: ~x"./link/text()"s,
      pub_date: ~x"./pubDate/text()"s,
      guid: ~x"./guid/text()"s,
      categories: ~x"./category/text()"ls
    )
    |> case do
      [] -> nil
      items -> Enum.map(items, &build_rss_item/1)
    end
  end

  # Parse Atom format entries
  defp parse_atom_entries(xml) do
    xml
    |> xpath(
      ~x"//entry"le,
      title: ~x"./title/text()"s,
      summary: ~x"./summary/text()"s,
      content: ~x"./content/text()"s,
      link: ~x"./link[@rel='alternate']/@href"s,
      pub_date: ~x"./published/text()"s,
      guid: ~x"./id/text()"s,
      categories: ~x"./category/@term"ls
    )
    |> case do
      [] -> nil
      entries -> Enum.map(entries, &build_rss_item/1)
    end
  end

  # Build an RssItem struct from parsed XML data
  defp build_rss_item(item_data) do
    # Use description/content field based on RSS vs Atom format
    description =
      clean_text(item_data[:description]) ||
        clean_text(item_data[:content]) ||
        clean_text(item_data[:summary])

    item = %RssItem{
      title: clean_text(item_data[:title]),
      description: description,
      link: clean_text(item_data[:link]),
      pub_date: clean_text(item_data[:pub_date]),
      guid: clean_text(item_data[:guid]),
      categories: item_data[:categories] || []
    }

    %{item | id: RssItem.generate_id(item)}
  end

  # Clean and normalize text content
  defp clean_text(nil), do: nil
  defp clean_text(""), do: nil

  defp clean_text(text) when is_binary(text) do
    text
    |> String.trim()
    |> case do
      "" -> nil
      cleaned -> cleaned
    end
  end
end
