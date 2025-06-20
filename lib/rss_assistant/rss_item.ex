defmodule RssAssistant.RssItem do
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
  Generates a unique ID for an RSS item.
  
  Uses the guid if available, otherwise creates a hash from link and title.
  """
  def generate_id(%{guid: guid}) when is_binary(guid) and guid != "", do: guid

  def generate_id(%{link: link, title: title}) when is_binary(link) and is_binary(title) do
    :crypto.hash(:sha256, "#{link}#{title}")
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  def generate_id(%{link: link}) when is_binary(link) do
    :crypto.hash(:sha256, link)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  def generate_id(%{title: title}) when is_binary(title) do
    :crypto.hash(:sha256, title)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end

  def generate_id(_) do
    # Fallback to a deterministic default ID for items with no identifiable content
    :crypto.hash(:sha256, "no-content")
    |> Base.encode16(case: :lower)
    |> String.slice(0, 16)
  end
end