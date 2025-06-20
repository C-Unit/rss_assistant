defmodule RssAssistant.FeedItem do
  @moduledoc """
  Represents a single item from an RSS or Atom feed.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          title: String.t() | nil,
          description: String.t() | nil,
          link: String.t() | nil,
          pub_date: String.t() | nil,
          guid: String.t() | nil,
          categories: [String.t()]
        }

  defstruct [
    :id,
    :title,
    :description,
    :link,
    :pub_date,
    :guid,
    categories: []
  ]

  @doc """
  Generates a unique ID for a feed item.

  Uses the guid if available, otherwise creates a hash from link and title.
  Returns a result tuple with the ID or an error.
  """
  def generate_id(%{guid: guid}) when is_binary(guid) and guid != "", do: {:ok, guid}

  def generate_id(%{link: link, title: title}) when is_binary(link) and is_binary(title) do
    id =
      :crypto.hash(:sha256, "#{link}#{title}")
      |> Base.encode16(case: :lower)
      |> String.slice(0, 16)

    {:ok, id}
  end

  def generate_id(%{link: link}) when is_binary(link) do
    id =
      :crypto.hash(:sha256, link)
      |> Base.encode16(case: :lower)
      |> String.slice(0, 16)

    {:ok, id}
  end

  def generate_id(%{title: title}) when is_binary(title) do
    id =
      :crypto.hash(:sha256, title)
      |> Base.encode16(case: :lower)
      |> String.slice(0, 16)

    {:ok, id}
  end

  def generate_id(_) do
    # Cannot generate ID for items with no identifiable content
    # Per user requirement: include the item anyway, don't exclude it
    {:error, :no_identifiable_content}
  end
end
