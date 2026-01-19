defmodule RssAssistantWeb.StripeWebhookPlug do
  @moduledoc """
  Plug for handling Stripe webhook requests.

  This plug:
  1. Reads the raw request body before Plug.Parsers
  2. Verifies the Stripe signature
  3. Parses the JSON payload into our Event struct
  4. Calls the configured handler

  ## Options
    * `:at` - The path to match for webhook requests (required)
    * `:handler` - Module implementing the webhook handler (required)
    * `:secret` - The webhook signing secret or MFA tuple (required)
  """

  @behaviour Plug

  import Plug.Conn

  require Logger

  alias RssAssistant.Stripe.Webhook

  @impl true
  def init(opts) do
    at = Keyword.fetch!(opts, :at)
    handler = Keyword.fetch!(opts, :handler)
    secret = Keyword.fetch!(opts, :secret)

    %{at: at, handler: handler, secret: secret}
  end

  @impl true
  def call(%Plug.Conn{request_path: path, method: "POST"} = conn, %{at: at} = opts)
      when path == at do
    with {:ok, body, conn} <- read_body(conn),
         [signature] <- get_req_header(conn, "stripe-signature"),
         secret <- resolve_secret(opts.secret),
         {:ok, event} <- Webhook.construct_event(body, signature, secret) do
      handle_event(conn, event, opts.handler)
    else
      {:error, reason} ->
        Logger.warning("Stripe webhook verification failed: #{inspect(reason)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: to_string(reason)}))
        |> halt()
    end
  end

  def call(conn, _opts), do: conn

  defp resolve_secret({m, f, a}), do: apply(m, f, a)
  defp resolve_secret(secret) when is_binary(secret), do: secret
  defp resolve_secret(secret) when is_function(secret, 0), do: secret.()

  defp handle_event(conn, event, handler) do
    case handler.handle_event(event) do
      :ok ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{received: true}))
        |> halt()

      {:ok, _} ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(200, Jason.encode!(%{received: true}))
        |> halt()

      {:error, reason} ->
        Logger.error("Stripe webhook handler error: #{inspect(reason)}")

        conn
        |> put_resp_content_type("application/json")
        |> send_resp(400, Jason.encode!(%{error: "Handler error"}))
        |> halt()
    end
  end
end
