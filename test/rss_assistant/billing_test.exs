defmodule RssAssistant.BillingTest do
  use RssAssistant.DataCase

  alias RssAssistant.Accounts
  alias RssAssistant.Billing
  alias RssAssistant.Billing.Subscription
  alias RssAssistant.Stripe.Event

  import RssAssistant.AccountsFixtures

  describe "handle_subscription_created/1" do
    setup do
      free_plan = free_plan_fixture()
      pro_plan = pro_plan_fixture()
      user = user_fixture()
      {:ok, user} = Accounts.set_stripe_customer_id(user, "cus_test123")

      %{user: user, free_plan: free_plan, pro_plan: pro_plan}
    end

    test "creates subscription and upgrades user to Pro", %{user: user, pro_plan: pro_plan} do
      stripe_subscription =
        build_stripe_subscription(%{
          id: "sub_test123",
          customer: user.stripe_customer_id,
          status: "active",
          current_period_start: DateTime.to_unix(DateTime.utc_now()),
          current_period_end: DateTime.to_unix(DateTime.add(DateTime.utc_now(), 30, :day)),
          price_id: pro_plan.stripe_price_id
        })

      assert {:ok, subscription} = Billing.handle_subscription_created(stripe_subscription)
      assert subscription.stripe_subscription_id == "sub_test123"
      assert subscription.status == "active"
      assert subscription.user_id == user.id

      # Verify user was upgraded to Pro
      updated_user = Accounts.get_user!(user.id)
      assert updated_user.plan_id == pro_plan.id
    end

    test "returns error when user not found" do
      stripe_subscription =
        build_stripe_subscription(%{
          id: "sub_test123",
          customer: "cus_nonexistent",
          status: "active"
        })

      assert {:error, :user_not_found} = Billing.handle_subscription_created(stripe_subscription)
    end

    test "is idempotent - returns existing subscription if already created", %{
      user: user,
      pro_plan: pro_plan
    } do
      stripe_subscription =
        build_stripe_subscription(%{
          id: "sub_test123",
          customer: user.stripe_customer_id,
          status: "active",
          price_id: pro_plan.stripe_price_id
        })

      {:ok, subscription1} = Billing.handle_subscription_created(stripe_subscription)
      {:ok, subscription2} = Billing.handle_subscription_created(stripe_subscription)

      assert subscription1.id == subscription2.id
    end
  end

  describe "handle_subscription_updated/1" do
    setup do
      free_plan = free_plan_fixture()
      pro_plan = pro_plan_fixture()
      user = user_fixture()
      {:ok, user} = Accounts.set_stripe_customer_id(user, "cus_test123")

      {:ok, subscription} =
        Billing.create_subscription(%{
          user_id: user.id,
          plan_id: pro_plan.id,
          stripe_customer_id: user.stripe_customer_id,
          stripe_subscription_id: "sub_test123",
          status: "active"
        })

      %{user: user, subscription: subscription, free_plan: free_plan, pro_plan: pro_plan}
    end

    test "updates subscription status", %{subscription: subscription, user: user} do
      stripe_subscription =
        build_stripe_subscription(%{
          id: subscription.stripe_subscription_id,
          customer: user.stripe_customer_id,
          status: "past_due",
          current_period_start: DateTime.to_unix(DateTime.utc_now()),
          current_period_end: DateTime.to_unix(DateTime.add(DateTime.utc_now(), 30, :day))
        })

      assert {:ok, updated} = Billing.handle_subscription_updated(stripe_subscription)
      assert updated.status == "past_due"
    end

    test "sets cancel_at_period_end when subscription is canceled", %{
      subscription: subscription,
      user: user
    } do
      stripe_subscription =
        build_stripe_subscription(%{
          id: subscription.stripe_subscription_id,
          customer: user.stripe_customer_id,
          status: "active",
          cancel_at_period_end: true,
          current_period_end: DateTime.to_unix(DateTime.add(DateTime.utc_now(), 30, :day))
        })

      assert {:ok, updated} = Billing.handle_subscription_updated(stripe_subscription)
      assert updated.cancel_at_period_end == true
    end

    test "creates subscription if not found but user exists", %{pro_plan: pro_plan} do
      # Use a fresh user without an existing subscription
      new_user = user_fixture()
      {:ok, new_user} = Accounts.set_stripe_customer_id(new_user, "cus_new_user")

      stripe_subscription =
        build_stripe_subscription(%{
          id: "sub_new",
          customer: new_user.stripe_customer_id,
          status: "active",
          price_id: pro_plan.stripe_price_id
        })

      assert {:ok, subscription} = Billing.handle_subscription_updated(stripe_subscription)
      assert subscription.stripe_subscription_id == "sub_new"
      assert subscription.user_id == new_user.id
    end

    test "returns user_not_found when subscription and user not found" do
      stripe_subscription =
        build_stripe_subscription(%{
          id: "sub_nonexistent",
          customer: "cus_nonexistent",
          status: "active"
        })

      assert {:error, :user_not_found} = Billing.handle_subscription_updated(stripe_subscription)
    end
  end

  describe "handle_subscription_deleted/1" do
    setup do
      free_plan = free_plan_fixture()
      pro_plan = pro_plan_fixture()
      user = user_fixture()
      {:ok, user} = Accounts.set_stripe_customer_id(user, "cus_test123")
      {:ok, _} = Accounts.change_user_plan(user, pro_plan.id)

      {:ok, subscription} =
        Billing.create_subscription(%{
          user_id: user.id,
          plan_id: pro_plan.id,
          stripe_customer_id: user.stripe_customer_id,
          stripe_subscription_id: "sub_test123",
          status: "active"
        })

      %{user: user, subscription: subscription, free_plan: free_plan, pro_plan: pro_plan}
    end

    test "marks subscription as canceled and downgrades user to Free", %{
      user: user,
      subscription: subscription,
      free_plan: free_plan
    } do
      canceled_at = DateTime.to_unix(DateTime.utc_now())

      stripe_subscription =
        build_stripe_subscription(%{
          id: subscription.stripe_subscription_id,
          canceled_at: canceled_at
        })

      assert {:ok, updated} = Billing.handle_subscription_deleted(stripe_subscription)
      assert updated.status == "canceled"
      assert updated.canceled_at != nil

      # Verify user was downgraded to Free
      updated_user = Accounts.get_user!(user.id)
      assert updated_user.plan_id == free_plan.id
    end

    test "returns error when subscription not found" do
      stripe_subscription =
        build_stripe_subscription(%{
          id: "sub_nonexistent",
          canceled_at: DateTime.to_unix(DateTime.utc_now())
        })

      assert {:error, :not_found} = Billing.handle_subscription_deleted(stripe_subscription)
    end
  end

  describe "handle_stripe_event/1" do
    setup do
      free_plan = free_plan_fixture()
      pro_plan = pro_plan_fixture()
      user = user_fixture()
      {:ok, user} = Accounts.set_stripe_customer_id(user, "cus_test123")

      %{user: user, free_plan: free_plan, pro_plan: pro_plan}
    end

    test "ignores subscription.created event (handled by subscription.updated)", %{
      user: user,
      pro_plan: pro_plan
    } do
      event =
        build_stripe_event("customer.subscription.created", %{
          id: "sub_test123",
          customer: user.stripe_customer_id,
          status: "active",
          price_id: pro_plan.stripe_price_id
        })

      assert {:ok, :ignored} = Billing.handle_stripe_event(event)
    end

    test "dispatches subscription.updated event", %{user: user, pro_plan: pro_plan} do
      # First create a subscription
      {:ok, _} =
        Billing.create_subscription(%{
          user_id: user.id,
          plan_id: pro_plan.id,
          stripe_customer_id: user.stripe_customer_id,
          stripe_subscription_id: "sub_test123",
          status: "active"
        })

      event =
        build_stripe_event("customer.subscription.updated", %{
          id: "sub_test123",
          customer: user.stripe_customer_id,
          status: "past_due"
        })

      assert {:ok, subscription} = Billing.handle_stripe_event(event)
      assert subscription.status == "past_due"
    end

    test "dispatches subscription.deleted event", %{user: user, pro_plan: pro_plan} do
      {:ok, _} =
        Billing.create_subscription(%{
          user_id: user.id,
          plan_id: pro_plan.id,
          stripe_customer_id: user.stripe_customer_id,
          stripe_subscription_id: "sub_test123",
          status: "active"
        })

      event =
        build_stripe_event("customer.subscription.deleted", %{
          id: "sub_test123",
          canceled_at: DateTime.to_unix(DateTime.utc_now())
        })

      assert {:ok, subscription} = Billing.handle_stripe_event(event)
      assert subscription.status == "canceled"
    end

    test "ignores unhandled event types" do
      event = build_stripe_event("customer.created", %{id: "cus_test"})

      assert {:ok, :ignored} = Billing.handle_stripe_event(event)
    end
  end

  describe "sync_user_plan/1" do
    setup do
      free_plan = free_plan_fixture()
      pro_plan = pro_plan_fixture()
      user = user_fixture()

      %{user: user, free_plan: free_plan, pro_plan: pro_plan}
    end

    test "upgrades user when subscription is active", %{
      user: user,
      free_plan: free_plan,
      pro_plan: pro_plan
    } do
      {:ok, subscription} =
        Billing.create_subscription(%{
          user_id: user.id,
          plan_id: pro_plan.id,
          stripe_customer_id: "cus_test",
          stripe_subscription_id: "sub_test",
          status: "active",
          current_period_end: NaiveDateTime.add(NaiveDateTime.utc_now(), 30 * 24 * 60 * 60)
        })

      # User starts on Free plan
      assert user.plan_id == free_plan.id

      {:ok, updated_user} = Billing.sync_user_plan(subscription)
      assert updated_user.plan_id == pro_plan.id
    end

    test "downgrades user when subscription is canceled", %{
      user: user,
      free_plan: free_plan,
      pro_plan: pro_plan
    } do
      # First upgrade user to Pro
      {:ok, user} = Accounts.change_user_plan(user, pro_plan.id)

      {:ok, subscription} =
        Billing.create_subscription(%{
          user_id: user.id,
          plan_id: pro_plan.id,
          stripe_customer_id: "cus_test",
          stripe_subscription_id: "sub_test",
          status: "canceled"
        })

      {:ok, updated_user} = Billing.sync_user_plan(subscription)
      assert updated_user.plan_id == free_plan.id
    end

    test "downgrades user when subscription period has ended", %{
      user: user,
      free_plan: free_plan,
      pro_plan: pro_plan
    } do
      {:ok, user} = Accounts.change_user_plan(user, pro_plan.id)

      {:ok, subscription} =
        Billing.create_subscription(%{
          user_id: user.id,
          plan_id: pro_plan.id,
          stripe_customer_id: "cus_test",
          stripe_subscription_id: "sub_test",
          status: "active",
          cancel_at_period_end: true,
          # Period ended yesterday
          current_period_end: NaiveDateTime.add(NaiveDateTime.utc_now(), -24 * 60 * 60)
        })

      {:ok, updated_user} = Billing.sync_user_plan(subscription)
      assert updated_user.plan_id == free_plan.id
    end
  end

  describe "Subscription.active?/1" do
    test "returns true for active subscription" do
      subscription = %Subscription{
        status: "active",
        cancel_at_period_end: false,
        current_period_end: NaiveDateTime.add(NaiveDateTime.utc_now(), 30 * 24 * 60 * 60)
      }

      assert Subscription.active?(subscription)
    end

    test "returns true for trialing subscription" do
      subscription = %Subscription{
        status: "trialing",
        cancel_at_period_end: false,
        current_period_end: NaiveDateTime.add(NaiveDateTime.utc_now(), 30 * 24 * 60 * 60)
      }

      assert Subscription.active?(subscription)
    end

    test "returns false for canceled subscription" do
      subscription = %Subscription{
        status: "canceled",
        cancel_at_period_end: false
      }

      refute Subscription.active?(subscription)
    end

    test "returns false for past_due subscription" do
      subscription = %Subscription{
        status: "past_due",
        cancel_at_period_end: false
      }

      refute Subscription.active?(subscription)
    end

    test "returns true for subscription canceling at period end but period not ended" do
      subscription = %Subscription{
        status: "active",
        cancel_at_period_end: true,
        current_period_end: NaiveDateTime.add(NaiveDateTime.utc_now(), 30 * 24 * 60 * 60)
      }

      assert Subscription.active?(subscription)
    end

    test "returns false for subscription canceling at period end and period has ended" do
      subscription = %Subscription{
        status: "active",
        cancel_at_period_end: true,
        current_period_end: NaiveDateTime.add(NaiveDateTime.utc_now(), -24 * 60 * 60)
      }

      refute Subscription.active?(subscription)
    end
  end

  # Helper functions to build mock Stripe objects

  defp build_stripe_subscription(attrs) do
    now = DateTime.to_unix(DateTime.utc_now())

    defaults = %{
      id: "sub_test",
      customer: "cus_test",
      status: "active",
      current_period_start: now,
      current_period_end: now + 30 * 24 * 60 * 60,
      cancel_at_period_end: false,
      canceled_at: nil,
      ended_at: nil,
      price_id: "price_test_pro"
    }

    merged = Map.merge(defaults, attrs)

    # Build a struct-like map that matches our Stripe.Subscription access patterns
    %{
      id: merged.id,
      customer: merged.customer,
      status: merged.status,
      cancel_at_period_end: merged.cancel_at_period_end,
      canceled_at: merged.canceled_at,
      ended_at: merged.ended_at,
      items: %{
        data: [
          %{
            current_period_start: merged.current_period_start,
            current_period_end: merged.current_period_end,
            price: %{id: merged.price_id}
          }
        ]
      }
    }
  end

  defp build_stripe_event(type, object_attrs) do
    object = build_stripe_subscription(object_attrs)

    %Event{
      id: "evt_test",
      type: type,
      data: %{object: object}
    }
  end
end
