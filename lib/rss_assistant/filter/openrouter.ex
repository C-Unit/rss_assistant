defmodule RssAssistant.Filter.OpenRouter do
  @moduledoc """
  A Filter implementation that uses OpenRouter (via OpenAI-compatible API) to intelligently
  determine whether RSS feed items should be included based on user prompts.

  This implementation sends the feed item content along with the user's
  filtering criteria to OpenRouter's API and uses structured JSON response format
  to ensure reliable, parseable responses with a defined schema.

  The structured response includes:
  - `should_include`: boolean indicating filtering decision
  - `reasoning`: string explaining the decision
  """

  @behaviour RssAssistant.Filter

  alias RssAssistant.FeedItem
  require Logger
  @model "nvidia/nemotron-3-nano-30b-a3b:free"

  @impl RssAssistant.Filter
  def should_include?(%FeedItem{} = item, prompt) when is_binary(prompt) do
    case analyze_with_openrouter(item, prompt) do
      {:ok, {should_include, reasoning}} when is_boolean(should_include) ->
        {:ok, {should_include, reasoning}}

      {:error, {:api_error, {:rate_limit, retry_after_seconds}}} ->
        Logger.info("OpenRouter API rate limited, retry after #{retry_after_seconds} seconds")
        {:retry, retry_after_seconds * 1000}

      {:error, reason} ->
        Logger.warning("OpenRouter filter failed: #{inspect(reason)}, including item by default")
        # Return error reason to higher level
        {:error, reason}
    end
  end

  defp analyze_with_openrouter(%FeedItem{} = item, prompt) do
    system_prompt = build_system_prompt()
    user_prompt = build_user_prompt(item, prompt)

    with {:ok, json_string} <- make_openrouter_request(system_prompt, user_prompt) do
      parse_json_response(json_string)
    end
  end

  defp build_system_prompt do
    """
    You are an RSS feed filtering assistant. Your job is to analyze RSS feed items and determine whether they should be included based on the user's filtering criteria.

    - Set "should_include" to false if the item matches what the user wants to filter OUT
    - Set "should_include" to true if the item should be kept in the feed
    - Provide a brief reasoning for your decision

    Consider the item's title, description, and categories when making your decision.
    """
  end

  defp build_user_prompt(%FeedItem{} = item, user_filter_prompt) do
    # Build a description of the feed item
    item_description = """
    RSS Feed Item:
    Title: #{item.title || "No title"}
    Description: #{item.description || "No description"}
    Categories: #{format_categories(item.categories)}
    Link: #{item.link || "No link"}
    """

    """
    User's filtering instruction: "#{user_filter_prompt}"

    #{item_description}

    Should this item be included in the filtered feed?
    """
  end

  defp format_categories([]), do: "None"
  defp format_categories(categories), do: Enum.join(categories, ", ")

  defp make_openrouter_request(system_prompt, user_prompt) do
    # Get API key from environment
    api_key = System.get_env("OPENROUTER_API_KEY")

    if is_nil(api_key) do
      {:error, :no_api_key}
    else
      # Create OpenAI client configured for OpenRouter
      client =
        OpenaiEx.new(api_key)
        |> OpenaiEx.with_base_url("https://openrouter.ai/api/v1")

      # Create chat completion request with structured JSON output
      request =
        OpenaiEx.Chat.Completions.new(
          model: @model,
          messages: [
            OpenaiEx.ChatMessage.system(system_prompt),
            OpenaiEx.ChatMessage.user(user_prompt)
          ],
          response_format: %{
            type: "json_schema",
            json_schema: %{
              name: "feed_filter_decision",
              strict: true,
              schema: %{
                type: "object",
                properties: %{
                  should_include: %{
                    type: "boolean",
                    description: "Whether the feed item should be included in the filtered feed"
                  },
                  reasoning: %{
                    type: "string",
                    description: "Brief explanation for the filtering decision"
                  }
                },
                required: ["should_include", "reasoning"],
                additionalProperties: false
              }
            }
          },
          temperature: 0.1,
          max_tokens: 200
        )

      # Make the request
      case safe_openrouter_call(client, request) do
        {:ok, json_string} when is_binary(json_string) ->
          {:ok, json_string}

        {:error, reason} ->
          {:error, {:api_error, reason}}

        other ->
          {:error, {:unexpected_response, other}}
      end
    end
  end

  defp safe_openrouter_call(client, request) do
    case OpenaiEx.Chat.Completions.create(client, request) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        {:ok, content}

      {:ok, response} ->
        Logger.warning("Unexpected response structure: #{inspect(response)}")
        {:error, :unexpected_response_structure}

      {:error, %{"error" => %{"code" => "rate_limit_exceeded", "message" => message}}} ->
        # Try to extract retry-after from message
        retry_after = extract_retry_after(message)
        {:error, {:rate_limit, retry_after}}

      {:error, error} ->
        {:error, {:request_failed, error}}
    end
  rescue
    error -> {:error, {:request_failed, error}}
  catch
    :exit, reason -> {:error, {:request_timeout, reason}}
  end

  defp extract_retry_after(message) when is_binary(message) do
    # Try to extract number of seconds from rate limit message
    case Regex.run(~r/retry after (\d+) second/i, message) do
      [_, seconds_str] ->
        String.to_integer(seconds_str)

      _ ->
        60
    end
  end

  defp extract_retry_after(_), do: 60

  defp parse_json_response(json_string) when is_binary(json_string) do
    Logger.debug("Parsing JSON response: #{inspect(json_string)}")

    case Jason.decode(json_string) do
      {:ok, %{"should_include" => should_include, "reasoning" => reasoning}}
      when is_boolean(should_include) and is_binary(reasoning) ->
        Logger.debug("OpenRouter filtering decision: #{should_include}, reasoning: #{reasoning}")
        {:ok, {should_include, reasoning}}

      {:ok, %{"should_include" => should_include}} when is_boolean(should_include) ->
        # Handle case where reasoning might be missing
        Logger.debug("OpenRouter filtering decision: #{should_include}")
        {:ok, {should_include, "No reasoning provided"}}

      {:ok, parsed} ->
        Logger.warning("Unexpected JSON format: #{inspect(parsed)}")
        {:error, :invalid_response_format}

      {:error, json_error} ->
        Logger.warning("Failed to parse JSON response: #{inspect(json_error)}")
        Logger.debug("Raw JSON string: #{inspect(json_string)}")
        {:error, :json_parse_error}
    end
  end
end
