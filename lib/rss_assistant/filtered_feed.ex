defmodule RssAssistant.FilteredFeed do
  use Ecto.Schema
  import Ecto.Changeset

  schema "filtered_feeds" do
    field :url, :string
    field :prompt, :string
    field :slug, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(filtered_feed, attrs) do
    filtered_feed
    |> cast(attrs, [:url, :prompt, :slug])
    |> validate_required([:url, :prompt])
    |> validate_format(:url, ~r/^https?:\/\//, message: "must be a valid URL")
    |> put_slug()
    |> unique_constraint(:slug)
  end

  defp put_slug(changeset) do
    if changeset.valid? and get_field(changeset, :slug) == nil do
      put_change(changeset, :slug, generate_slug())
    else
      changeset
    end
  end

  defp generate_slug do
    :crypto.strong_rand_bytes(8)
    |> Base.url_encode64()
    |> binary_part(0, 8)
    |> String.downcase()
  end
end