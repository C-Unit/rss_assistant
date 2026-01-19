defmodule RssAssistant.Stripe.WebhookTest do
  use ExUnit.Case, async: true

  alias RssAssistant.Stripe.Webhook

  @secret "whsec_test_secret"

  describe "construct_event/4" do
    test "verifies valid signature and parses event" do
      payload =
        Jason.encode!(%{
          "id" => "evt_test123",
          "type" => "customer.subscription.created",
          "data" => %{
            "object" => %{
              "id" => "sub_test123",
              "object" => "subscription",
              "customer" => "cus_test123",
              "status" => "active",
              "items" => %{
                "data" => [
                  %{
                    "id" => "si_test",
                    "current_period_start" => 1_609_459_200,
                    "current_period_end" => 1_612_137_600,
                    "price" => %{"id" => "price_test"}
                  }
                ]
              }
            }
          },
          "created" => 1_609_459_200,
          "api_version" => "2025-01-27.acacia"
        })

      timestamp = System.system_time(:second)
      signature = compute_signature(payload, timestamp, @secret)
      header = "t=#{timestamp},v1=#{signature}"

      assert {:ok, event} = Webhook.construct_event(payload, header, @secret)
      assert event.id == "evt_test123"
      assert event.type == "customer.subscription.created"
    end

    test "rejects invalid signature" do
      payload = Jason.encode!(%{"id" => "evt_test"})
      timestamp = System.system_time(:second)
      header = "t=#{timestamp},v1=invalid_signature"

      assert {:error, :invalid_signature} = Webhook.construct_event(payload, header, @secret)
    end

    test "rejects expired timestamp" do
      payload = Jason.encode!(%{"id" => "evt_test"})
      old_timestamp = System.system_time(:second) - 400
      signature = compute_signature(payload, old_timestamp, @secret)
      header = "t=#{old_timestamp},v1=#{signature}"

      assert {:error, :timestamp_too_old} = Webhook.construct_event(payload, header, @secret)
    end

    test "rejects missing timestamp" do
      payload = Jason.encode!(%{"id" => "evt_test"})
      header = "v1=some_signature"

      assert {:error, :missing_timestamp} = Webhook.construct_event(payload, header, @secret)
    end

    test "rejects missing signature" do
      payload = Jason.encode!(%{"id" => "evt_test"})
      timestamp = System.system_time(:second)
      header = "t=#{timestamp}"

      assert {:error, :missing_signature} = Webhook.construct_event(payload, header, @secret)
    end
  end

  describe "parse_signature_header/1" do
    test "parses valid header" do
      header = "t=1234567890,v1=abc123"
      assert {:ok, 1_234_567_890, ["abc123"]} = Webhook.parse_signature_header(header)
    end

    test "handles whitespace" do
      header = "t=1234567890, v1=abc123"
      assert {:ok, 1_234_567_890, ["abc123"]} = Webhook.parse_signature_header(header)
    end

    test "returns error for invalid header" do
      assert {:error, :invalid_header} = Webhook.parse_signature_header(nil)
    end
  end

  defp compute_signature(payload, timestamp, secret) do
    signed_payload = "#{timestamp}.#{payload}"

    :crypto.mac(:hmac, :sha256, secret, signed_payload)
    |> Base.encode16(case: :lower)
  end
end
