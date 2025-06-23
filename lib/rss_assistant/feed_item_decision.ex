defmodule RssAssistant.FeedItemDecision do
  @moduledoc """
  Represents a filtering decision for a specific feed item.
  
  This struct contains the decision result from a filter implementation,
  including the item ID, whether it should be included, and reasoning.
  """

  @type t :: %__MODULE__{
          item_id: String.t() | nil,
          should_include: boolean(),
          reasoning: String.t() | nil,
          timestamp: DateTime.t() | nil
        }

  defstruct [
    :item_id,
    :should_include,
    :reasoning,
    :timestamp
  ]

  @doc """
  Creates a new FeedItemDecision struct.
  """
  def new(item_id, should_include, reasoning \\ nil) do
    %__MODULE__{
      item_id: item_id,
      should_include: should_include,
      reasoning: reasoning,
      timestamp: DateTime.utc_now()
    }
  end
end

defmodule RssAssistant.FeedItemDecisionSchema do
  @moduledoc """
  Ecto schema for persisting feed item decisions.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "feed_item_decisions" do
    field :item_id, :string
    field :should_include, :boolean
    field :reasoning, :string
    field :filtered_feed_id, :id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(feed_item_decision, attrs) do
    feed_item_decision
    |> cast(attrs, [:item_id, :should_include, :reasoning, :filtered_feed_id])
    |> validate_required([:item_id, :should_include, :filtered_feed_id])
    |> unique_constraint([:item_id, :filtered_feed_id])
  end
end