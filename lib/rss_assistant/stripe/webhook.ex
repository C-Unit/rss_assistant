defmodule RssAssistant.Stripe.Webhook do
  @moduledoc """
  Stripe webhook signature verification.

  Implements the Stripe webhook signature scheme using HMAC-SHA256.
  See: https://stripe.com/docs/webhooks/signatures
  """

  alias RssAssistant.Stripe.Event

  @default_tolerance 300

  @doc """
  Constructs and verifies a Stripe event from a webhook payload.

  ## Parameters
    * `payload` - The raw request body (string)
    * `signature` - The Stripe-Signature header value
    * `secret` - The webhook signing secret (whsec_...)
    * `tolerance` - Maximum allowed age in seconds (default: 300)

  ## Returns
    * `{:ok, event}` - Successfully verified and parsed event
    * `{:error, reason}` - Verification or parsing failed
  """
  def construct_event(payload, signature, secret, tolerance \\ @default_tolerance) do
    with {:ok, timestamp, signatures} <- parse_signature_header(signature),
         :ok <- verify_timestamp(timestamp, tolerance),
         :ok <- verify_signature(payload, timestamp, signatures, secret) do
      payload
      |> Jason.decode!()
      |> Event.from_map()
      |> then(&{:ok, &1})
    end
  end

  @doc """
  Parses the Stripe-Signature header.

  Returns `{:ok, timestamp, signatures}` or `{:error, reason}`.
  """
  def parse_signature_header(header) when is_binary(header) do
    parts =
      header
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.map(&parse_header_part/1)
      |> Enum.into(%{})

    timestamp = Map.get(parts, "t")
    signatures = Map.get(parts, "v1", [])

    cond do
      is_nil(timestamp) ->
        {:error, :missing_timestamp}

      signatures == [] ->
        {:error, :missing_signature}

      true ->
        case Integer.parse(timestamp) do
          {ts, ""} -> {:ok, ts, signatures}
          _ -> {:error, :invalid_timestamp}
        end
    end
  end

  def parse_signature_header(_), do: {:error, :invalid_header}

  defp parse_header_part(part) do
    case String.split(part, "=", parts: 2) do
      ["t", value] -> {"t", value}
      ["v1", value] -> {"v1", [value]}
      _ -> {nil, nil}
    end
  end

  @doc """
  Verifies the timestamp is within the tolerance window.
  """
  def verify_timestamp(timestamp, tolerance) do
    now = System.system_time(:second)

    if now - timestamp <= tolerance do
      :ok
    else
      {:error, :timestamp_too_old}
    end
  end

  @doc """
  Verifies the webhook signature using HMAC-SHA256.
  """
  def verify_signature(payload, timestamp, signatures, secret) do
    signed_payload = "#{timestamp}.#{payload}"
    expected_signature = compute_signature(signed_payload, secret)

    if Enum.any?(signatures, &secure_compare(&1, expected_signature)) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  defp compute_signature(payload, secret) do
    :crypto.mac(:hmac, :sha256, secret, payload)
    |> Base.encode16(case: :lower)
  end

  defp secure_compare(a, b) when byte_size(a) != byte_size(b), do: false

  defp secure_compare(a, b) do
    a_bytes = :binary.bin_to_list(a)
    b_bytes = :binary.bin_to_list(b)

    Enum.zip(a_bytes, b_bytes)
    |> Enum.reduce(0, fn {x, y}, acc -> Bitwise.bor(acc, Bitwise.bxor(x, y)) end)
    |> Kernel.==(0)
  end
end
