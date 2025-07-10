defmodule RssAssistant.FeedParser do
  @moduledoc """
  Parses RSS and Atom feeds into structured FeedItem data.

  Supports both RSS 2.0 and Atom feed formats using SweetXml for parsing.
  """

  import SweetXml
  alias RssAssistant.FeedItem

  @doc """
  Parses an RSS or Atom feed XML string into a list of FeedItem structs.

  ## Examples

      iex> xml = "<rss><channel><item><title>Test</title></item></channel></rss>"
      iex> RssAssistant.FeedParser.parse_feed(xml)
      {:ok, [%FeedItem{title: "Test", ...}]}
      
      iex> RssAssistant.FeedParser.parse_feed("invalid xml")
      {:error, :invalid_xml}
  """
  @spec parse_feed(String.t()) :: {:ok, [FeedItem.t()]} | {:error, :invalid_xml | :unknown_format}
  def parse_feed(xml_string) when is_binary(xml_string) do
    case detect_feed_type(xml_string) do
      {:rss, parsed_xml} ->
        items = parse_rss_items(parsed_xml) || []
        {:ok, items}

      {:atom, parsed_xml} ->
        items = parse_atom_entries(parsed_xml) || []
        {:ok, items}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def parse_feed(_), do: {:error, :invalid_xml}

  @doc """
  Detects the feed type (RSS or Atom) and returns parsed XML.

  ## Returns

    * `{:rss, parsed_xml}` - RSS 2.0 feed detected
    * `{:atom, parsed_xml}` - Atom feed detected  
    * `{:error, :invalid_xml}` - XML parsing failed
    * `{:error, :unknown_format}` - Neither RSS nor Atom format detected
  """
  @spec detect_feed_type(String.t()) ::
          {:rss, term()} | {:atom, term()} | {:error, :invalid_xml | :unknown_format}
  def detect_feed_type(xml_string) when is_binary(xml_string) do
    parsed_xml = parse(xml_string)

    cond do
      xpath(parsed_xml, ~x"//rss") ->
        {:rss, parsed_xml}

      xpath(parsed_xml, ~x"//feed") ->
        {:atom, parsed_xml}

      true ->
        {:error, :unknown_format}
    end
  rescue
    _error -> {:error, :invalid_xml}
  catch
    :exit, _reason -> {:error, :invalid_xml}
  end

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
      items -> Enum.map(items, &build_feed_item/1)
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
      entries -> Enum.map(entries, &build_feed_item/1)
    end
  end

  # Build a FeedItem struct from parsed XML data
  defp build_feed_item(item_data) do
    # Use description/content field based on RSS vs Atom format
    description =
      clean_text(item_data[:description]) ||
        clean_text(item_data[:content]) ||
        clean_text(item_data[:summary])

    item = %FeedItem{
      title: clean_text(item_data[:title]),
      description: description,
      link: clean_text(item_data[:link]),
      pub_date: clean_text(item_data[:pub_date]),
      guid: clean_text(item_data[:guid]),
      categories: item_data[:categories] || []
    }

    # Handle both success and error cases for ID generation
    # Per user requirement: include items even when ID generation fails
    generated_id =
      case FeedItem.generate_id(item) do
        {:ok, generated_id} -> generated_id
        {:error, :no_identifiable_content} -> nil
      end

    %{item | generated_id: generated_id}
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
