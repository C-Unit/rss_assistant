defmodule RssAssistant.Billing.StripeWebhookHandlerTest do
  use RssAssistant.DataCase

  alias RssAssistant.Accounts
  alias RssAssistant.Billing.StripeWebhookHandler

  import RssAssistant.AccountsFixtures
  import RssAssistant.BillingFixtures

  describe "handle_event/1 for checkout.session.completed" do
    setup do
      free_plan_fixture()
      pro_plan = pro_plan_fixture()
      user = user_fixture()
      %{user: user, pro_plan: pro_plan}
    end

    test "upgrades user to Pro", %{user: user, pro_plan: pro_plan} do
      session =
        checkout_session_fixture(%{
          client_reference_id: to_string(user.id),
          customer: "cus_test_123",
          subscription: "sub_test_456"
        })

      event = %Stripe.Event{
        type: "checkout.session.completed",
        data: %{object: session}
      }

      assert :ok = StripeWebhookHandler.handle_event(event)

      updated_user = Accounts.get_user!(user.id)
      assert updated_user.plan_id == pro_plan.id
    end
  end

  describe "handle_event/1 for customer.subscription.updated" do
    setup do
      free_plan_fixture()
      pro_plan_fixture()
      user = user_fixture()

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

      event = %Stripe.Event{
        type: "customer.subscription.updated",
        data: %{object: subscription}
      }

      assert :ok = StripeWebhookHandler.handle_event(event)

      updated_user = Accounts.get_user!(user.id)
      assert updated_user.stripe_subscription_status == "past_due"
    end
  end

  describe "handle_event/1 for customer.subscription.deleted" do
    setup do
      free_plan = free_plan_fixture()
      pro_plan = pro_plan_fixture()
      user = user_fixture()

      {:ok, user} = Accounts.change_user_plan(user, pro_plan.id)

      {:ok, user} =
        user
        |> Accounts.User.stripe_changeset(%{
          stripe_customer_id: "cus_test_123",
          stripe_subscription_id: "sub_test_456",
          stripe_subscription_status: "active"
        })
        |> Repo.update()

      %{user: user, free_plan: free_plan}
    end

    test "downgrades user to Free", %{user: user, free_plan: free_plan} do
      subscription = subscription_fixture(%{id: "sub_test_456"})

      event = %Stripe.Event{
        type: "customer.subscription.deleted",
        data: %{object: subscription}
      }

      assert :ok = StripeWebhookHandler.handle_event(event)

      updated_user = Accounts.get_user!(user.id)
      assert updated_user.plan_id == free_plan.id
    end
  end

  describe "handle_event/1 for unhandled events" do
    test "returns :ok for invoice.payment_failed" do
      event = %Stripe.Event{
        type: "invoice.payment_failed",
        data: %{object: %{"customer" => "cus_test_123"}}
      }

      assert :ok = StripeWebhookHandler.handle_event(event)
    end

    test "returns :ok for unknown event types" do
      event = %Stripe.Event{
        type: "some.unknown.event",
        data: %{object: %{}}
      }

      assert :ok = StripeWebhookHandler.handle_event(event)
    end
  end
end
