defmodule RssAssistant.Filter.Gemini do
  @moduledoc """
  A Filter implementation that uses Google's Gemini AI to intelligently
  determine whether RSS feed items should be included based on user prompts.

  This implementation sends the feed item content along with the user's
  filtering criteria to Gemini AI and uses structured JSON response configuration
  to ensure reliable, parseable responses with a defined schema.

  The structured response includes:
  - `should_include`: boolean indicating filtering decision
  - `reasoning`: string explaining the decision
  """

  @behaviour RssAssistant.Filter

  alias RssAssistant.FeedItem
  require Logger
  @model "gemini-2.5-flash-lite-preview-06-17"

  @impl RssAssistant.Filter
  def should_include?(%FeedItem{} = item, prompt) when is_binary(prompt) do
    case analyze_with_gemini(item, prompt) do
      {:ok, {should_include, reasoning}} when is_boolean(should_include) ->
        {:ok, {should_include, reasoning}}

      {:error, {:api_error, {:rate_limit, retry_after_seconds}}} ->
        Logger.info("Gemini API rate limited, retry after #{retry_after_seconds} seconds")
        {:retry, retry_after_seconds * 1000}

      {:error, reason} ->
        Logger.warning("Gemini filter failed: #{inspect(reason)}, including item by default")
        # Return error reason to higher level
        {:error, reason}
    end
  end

  defp analyze_with_gemini(%FeedItem{} = item, prompt) do
    system_prompt = build_system_prompt()
    user_prompt = build_user_prompt(item, prompt)
    full_prompt = "#{system_prompt}\n\n#{user_prompt}"

    with {:ok, json_string} <- make_gemini_request(full_prompt),
         {:ok, {should_include, reasoning}} <- parse_json_response(json_string) do
      {:ok, {should_include, reasoning}}
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

  defp make_gemini_request(prompt) do
    # Configure structured JSON response with schema
    generation_config = %Gemini.Types.GenerationConfig{
      response_mime_type: "application/json",
      response_schema: %{
        "type" => "object",
        "properties" => %{
          "should_include" => %{
            "type" => "boolean",
            "description" => "Whether the feed item should be included in the filtered feed"
          },
          "reasoning" => %{
            "type" => "string",
            "description" => "Brief explanation for the filtering decision"
          }
        },
        "required" => ["should_include", "reasoning"]
      },
      # Low temperature for consistent responses
      temperature: 0.1,
      max_output_tokens: 200
    }

    # Use the Gemini client to generate structured content - handle exceptions
    with {:ok, json_string} when is_binary(json_string) <-
           safe_gemini_call(prompt, generation_config) do
      {:ok, json_string}
    else
      {:error, reason} -> {:error, {:api_error, reason}}
      other -> {:error, {:unexpected_response, other}}
    end
  end

  defp safe_gemini_call(prompt, generation_config) do
    case Gemini.Generate.text(prompt, generation_config: generation_config, model: @model) do
      {:ok, result} ->
        {:ok, result}

      {:error, rate_limited = %Gemini.Error{api_reason: 429}} ->
        {:error, extract_rate_limit_info(rate_limited)}

      {:error, error} ->
        {:error, {:request_failed, error}}
    end
  rescue
    error -> {:error, {:request_failed, error}}
  catch
    :exit, reason -> {:error, {:request_timeout, reason}}
  end

  defp extract_rate_limit_info(%Gemini.Error{api_reason: 429, message: %{"details" => details}}) do
    retry_delay = get_retry_delay(%{"details" => details})
    {:rate_limit, retry_delay}
  end

  defp extract_rate_limit_info(_fallback), do: 60

  defp get_retry_delay(%{"details" => details}) when is_list(details) do
    Enum.find_value(details, 60, fn
      %{"@type" => "type.googleapis.com/google.rpc.RetryInfo", "retryDelay" => retry_delay} ->
        retry_delay
        |> String.replace("s", "")
        |> String.to_integer()

      _ ->
        nil
    end)
  end

  defp get_retry_delay(_), do: 60

  defp parse_json_response(json_string) when is_binary(json_string) do
    Logger.debug("Parsing JSON response: #{inspect(json_string)}")

    case Jason.decode(json_string) do
      {:ok, %{"should_include" => should_include, "reasoning" => reasoning}}
      when is_boolean(should_include) and is_binary(reasoning) ->
        Logger.debug("Gemini filtering decision: #{should_include}, reasoning: #{reasoning}")
        {:ok, {should_include, reasoning}}

      {:ok, %{"should_include" => should_include}} when is_boolean(should_include) ->
        # Handle case where reasoning might be missing
        Logger.debug("Gemini filtering decision: #{should_include}")
        {:ok, {should_include, "No reasoning provided"}}

      {:ok, parsed} ->
        Logger.warning("Unexpected Gemini JSON format: #{inspect(parsed)}")
        {:error, :invalid_response_format}

      {:error, json_error} ->
        Logger.warning("Failed to parse Gemini JSON response: #{inspect(json_error)}")
        Logger.debug("Raw JSON string: #{inspect(json_string)}")
        {:error, :json_parse_error}
    end
  end
end
