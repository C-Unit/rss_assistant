defmodule RssAssistant.Accounts.PlanTest do
  use RssAssistant.DataCase

  alias RssAssistant.Accounts.Plan

  describe "changeset/2" do
    test "valid changeset with all required fields" do
      attrs = %{
        name: "Basic",
        max_feeds: 5,
        price: Decimal.new("9.99")
      }

      changeset = Plan.changeset(%Plan{}, attrs)
      assert changeset.valid?
    end

    test "requires name" do
      attrs = %{max_feeds: 5, price: Decimal.new("9.99")}
      changeset = Plan.changeset(%Plan{}, attrs)
      
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
    end

    test "requires max_feeds" do
      attrs = %{name: "Basic", price: Decimal.new("9.99")}
      changeset = Plan.changeset(%Plan{}, attrs)
      
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).max_feeds
    end

    test "requires price" do
      attrs = %{name: "Basic", max_feeds: 5}
      changeset = Plan.changeset(%Plan{}, attrs)
      
      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).price
    end
  end

end