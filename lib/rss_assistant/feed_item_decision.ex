defmodule RssAssistant.FeedItemDecision do
  @moduledoc """
  Ecto schema for persisting feed item decisions.

  Represents a filtering decision for a specific feed item,
  including the item ID, whether it should be included, and reasoning.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "feed_item_decisions" do
    field :item_id, :string
    field :should_include, :boolean
    field :reasoning, :string
    field :title, :string
    field :description, :string
    field :filtered_feed_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a feed item decision.
  """
  def changeset(feed_item_decision, attrs) do
    feed_item_decision
    |> cast(attrs, [:item_id, :should_include, :reasoning, :title, :description, :filtered_feed_id])
    |> validate_required([:item_id, :should_include, :filtered_feed_id])
    |> unique_constraint([:item_id, :filtered_feed_id])
  end
end
