defmodule RssAssistant.BillingTest do
  use RssAssistant.DataCase

  alias RssAssistant.Accounts
  alias RssAssistant.Billing

  import RssAssistant.AccountsFixtures
  import RssAssistant.BillingFixtures

  describe "handle_checkout_completed/1" do
    setup do
      free_plan_fixture()
      pro_plan = pro_plan_fixture()
      user = user_fixture()
      %{user: user, pro_plan: pro_plan}
    end

    test "upgrades user to Pro plan", %{user: user, pro_plan: pro_plan} do
      session =
        checkout_session_fixture(%{
          client_reference_id: to_string(user.id),
          customer: "cus_test_123",
          subscription: "sub_test_456"
        })

      assert {:ok, :upgraded} = Billing.handle_checkout_completed(session)

      updated_user = Accounts.get_user!(user.id)
      assert updated_user.plan_id == pro_plan.id
      assert updated_user.stripe_customer_id == "cus_test_123"
      assert updated_user.stripe_subscription_id == "sub_test_456"
      assert updated_user.stripe_subscription_status == "active"
    end

    test "returns error when user not found" do
      session =
        checkout_session_fixture(%{
          client_reference_id: "999999",
          customer: "cus_test_123",
          subscription: "sub_test_456"
        })

      assert {:error, :user_not_found} = Billing.handle_checkout_completed(session)
    end

    test "is idempotent - can be called multiple times", %{user: user} do
      session =
        checkout_session_fixture(%{
          client_reference_id: to_string(user.id),
          customer: "cus_test_123",
          subscription: "sub_test_456"
        })

      assert {:ok, :upgraded} = Billing.handle_checkout_completed(session)
      assert {:ok, :upgraded} = Billing.handle_checkout_completed(session)

      updated_user = Accounts.get_user!(user.id)
      assert updated_user.stripe_customer_id == "cus_test_123"
    end
  end

  describe "handle_subscription_updated/1" do
    setup do
      free_plan_fixture()
      pro_plan_fixture()
      user = user_fixture()

      # Simulate user already has subscription
      {:ok, user} =
        user
        |> Accounts.User.stripe_changeset(%{
          stripe_customer_id: "cus_test_123",
          stripe_subscription_id: "sub_test_456",
          stripe_subscription_status: "active"
        })
        |> Repo.update()

      %{user: user}
    end

    test "updates subscription status", %{user: user} do
      subscription =
        subscription_fixture(%{
          id: "sub_test_456",
          status: "past_due"
        })

      assert {:ok, :updated} = Billing.handle_subscription_updated(subscription)

      updated_user = Accounts.get_user!(user.id)
      assert updated_user.stripe_subscription_status == "past_due"
    end

    test "returns ok when user not found for subscription" do
      subscription =
        subscription_fixture(%{
          id: "sub_unknown",
          status: "active"
        })

      assert {:ok, :user_not_found} = Billing.handle_subscription_updated(subscription)
    end
  end

  describe "handle_subscription_deleted/1" do
    setup do
      free_plan = free_plan_fixture()
      pro_plan = pro_plan_fixture()
      user = user_fixture()

      # Upgrade user to Pro with subscription
      {:ok, user} = Accounts.change_user_plan(user, pro_plan.id)

      {:ok, user} =
        user
        |> Accounts.User.stripe_changeset(%{
          stripe_customer_id: "cus_test_123",
          stripe_subscription_id: "sub_test_456",
          stripe_subscription_status: "active"
        })
        |> Repo.update()

      %{user: user, free_plan: free_plan, pro_plan: pro_plan}
    end

    test "downgrades user to Free plan", %{user: user, free_plan: free_plan} do
      subscription = subscription_fixture(%{id: "sub_test_456"})

      assert {:ok, :downgraded} = Billing.handle_subscription_deleted(subscription)

      updated_user = Accounts.get_user!(user.id)
      assert updated_user.plan_id == free_plan.id
      assert updated_user.stripe_subscription_id == nil
      assert updated_user.stripe_subscription_status == nil
      # Customer ID is preserved
      assert updated_user.stripe_customer_id == "cus_test_123"
    end

    test "returns ok when user not found for subscription" do
      subscription = subscription_fixture(%{id: "sub_unknown"})

      assert {:ok, :user_not_found} = Billing.handle_subscription_deleted(subscription)
    end
  end
end
