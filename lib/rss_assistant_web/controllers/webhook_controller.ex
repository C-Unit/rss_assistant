defmodule RssAssistantWeb.WebhookController do
  use RssAssistantWeb, :controller
  require Logger

  alias RssAssistant.Billing
  alias RssAssistant.Billing.StripeService

  @doc """
  Handles incoming Stripe webhooks.
  """
  def stripe(conn, _params) do
    # Read the raw body
    {:ok, payload, _conn} = Plug.Conn.read_body(conn)

    # Get the Stripe signature from headers
    signature = get_req_header(conn, "stripe-signature") |> List.first()

    case StripeService.construct_webhook_event(payload, signature) do
      {:ok, event} ->
        Logger.info("Received Stripe webhook: #{event.type}")

        case Billing.handle_stripe_event(event) do
          {:ok, _result} ->
            Logger.info("Successfully processed Stripe webhook: #{event.type}")
            json(conn, %{received: true})

          {:error, reason} ->
            Logger.error("Error processing Stripe webhook: #{inspect(reason)}")
            json(conn, %{received: true})
        end

      {:error, error} ->
        Logger.error("Invalid webhook signature: #{inspect(error)}")

        conn
        |> put_status(400)
        |> json(%{error: "Invalid signature"})
    end
  end
end
