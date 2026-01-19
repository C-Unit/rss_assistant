defmodule RssAssistant.Stripe.SubscriptionTest do
  use ExUnit.Case, async: true

  alias RssAssistant.Stripe.{Price, Subscription, SubscriptionItem}

  describe "Subscription.from_map/1" do
    test "parses subscription from API response" do
      map = %{
        "id" => "sub_1Pgc6xB7WZ01zgkWJMvZp5ja",
        "object" => "subscription",
        "customer" => "cus_test123",
        "status" => "active",
        "cancel_at_period_end" => false,
        "canceled_at" => nil,
        "ended_at" => nil,
        "billing_cycle_anchor" => 1_609_459_200,
        "created" => 1_609_459_200,
        "metadata" => %{"user_id" => "123"},
        "items" => %{
          "data" => [
            %{
              "id" => "si_QXhVBoJ7NQdNXh",
              "object" => "subscription_item",
              "current_period_start" => 1_896_570_518,
              "current_period_end" => 976_287_773,
              "price" => %{
                "id" => "price_1PgafmB7WZ01zgkW6dKueIc5",
                "currency" => "usd",
                "unit_amount" => 2000
              },
              "quantity" => 1,
              "subscription" => "sub_1Pgc6xB7WZ01zgkWJMvZp5ja"
            }
          ]
        }
      }

      subscription = Subscription.from_map(map)

      assert %Subscription{} = subscription
      assert subscription.id == "sub_1Pgc6xB7WZ01zgkWJMvZp5ja"
      assert subscription.customer == "cus_test123"
      assert subscription.status == "active"
      assert subscription.cancel_at_period_end == false
      assert subscription.metadata == %{"user_id" => "123"}

      assert %{data: [item]} = subscription.items
      assert %SubscriptionItem{} = item
      assert item.id == "si_QXhVBoJ7NQdNXh"
      assert item.current_period_start == 1_896_570_518
      assert item.current_period_end == 976_287_773
      assert %Price{} = item.price
      assert item.price.id == "price_1PgafmB7WZ01zgkW6dKueIc5"
    end

    test "handles nil items" do
      map = %{
        "id" => "sub_test",
        "customer" => "cus_test",
        "status" => "active",
        "items" => nil
      }

      subscription = Subscription.from_map(map)
      assert subscription.items == nil
    end
  end

  describe "SubscriptionItem.from_map/1" do
    test "parses subscription item with period fields from official fixture" do
      map = %{
        "id" => "si_QXhVBoJ7NQdNXh",
        "object" => "subscription_item",
        "current_period_end" => 976_287_773,
        "current_period_start" => 1_896_570_518,
        "price" => %{
          "id" => "price_1PgafmB7WZ01zgkW6dKueIc5",
          "currency" => "usd",
          "unit_amount" => 2000
        },
        "quantity" => 1,
        "subscription" => "sub_1Pgc6xB7WZ01zgkWJMvZp5ja"
      }

      item = SubscriptionItem.from_map(map)

      assert %SubscriptionItem{} = item
      assert item.id == "si_QXhVBoJ7NQdNXh"
      assert item.current_period_start == 1_896_570_518
      assert item.current_period_end == 976_287_773
      assert item.quantity == 1
      assert item.subscription == "sub_1Pgc6xB7WZ01zgkWJMvZp5ja"
      assert %Price{} = item.price
      assert item.price.id == "price_1PgafmB7WZ01zgkW6dKueIc5"
      assert item.price.unit_amount == 2000
    end
  end
end
