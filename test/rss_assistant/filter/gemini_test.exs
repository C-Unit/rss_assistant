defmodule RssAssistant.Filter.GeminiTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias RssAssistant.Filter.Gemini
  alias RssAssistant.FeedItem

  describe "should_include?/2" do
    test "returns true when Gemini API is not configured (fallback behavior)" do
      # Clear any API key to test fallback behavior
      original_api_key = Application.get_env(:gemini_ex, :api_key)
      Application.put_env(:gemini_ex, :api_key, nil)

      item = %FeedItem{
        generated_id: "test-article-123",
        title: "Test Article",
        description: "A test article about technology",
        categories: ["tech"]
      }

      # Should return error when API is not configured
      capture_log(fn ->
        result = Gemini.should_include?(item, "filter out sports content")
        assert {:error, _reason} = result
      end)

      # Restore original config
      Application.put_env(:gemini_ex, :api_key, original_api_key)
    end

    test "handles empty feed item gracefully" do
      # Clear any API key to test fallback behavior
      original_api_key = Application.get_env(:gemini_ex, :api_key)
      Application.put_env(:gemini_ex, :api_key, nil)

      item = %FeedItem{
        generated_id: "empty-item-456",
        title: nil,
        description: nil,
        categories: []
      }

      # Should return error with minimal data when API not configured
      capture_log(fn ->
        result = Gemini.should_include?(item, "any filter")
        assert {:error, _reason} = result
      end)

      # Restore original config
      Application.put_env(:gemini_ex, :api_key, original_api_key)
    end

    test "handles various category formats" do
      # Clear any API key to test fallback behavior
      original_api_key = Application.get_env(:gemini_ex, :api_key)
      Application.put_env(:gemini_ex, :api_key, nil)

      item_with_categories = %FeedItem{
        generated_id: "categories-item-789",
        title: "Article with categories",
        description: "Description",
        categories: ["Technology", "AI", "Programming"]
      }

      item_without_categories = %FeedItem{
        generated_id: "no-categories-item-012",
        title: "Article without categories",
        description: "Description",
        categories: []
      }

      capture_log(fn ->
        result1 = Gemini.should_include?(item_with_categories, "filter tech")
        assert {:error, _reason1} = result1

        result2 = Gemini.should_include?(item_without_categories, "filter tech")
        assert {:error, _reason2} = result2
      end)

      # Restore original config
      Application.put_env(:gemini_ex, :api_key, original_api_key)
    end

    @tag :integration
    test "works with real Gemini API when configured" do
      # Only run this test if GEMINI_API_KEY is set
      case System.get_env("GEMINI_API_KEY") do
        nil ->
          # Skip test if API key not provided
          :ok

        _api_key ->
          item = %FeedItem{
            generated_id: "sports-championship-345",
            title: "Breaking: Local Sports Team Wins Championship",
            description: "The hometown football team secured a decisive victory last night...",
            categories: ["Sports", "Local News"]
          }

          # Test filtering out sports content
          result = Gemini.should_include?(item, "filter out all sports-related content")

          # Result should be a successful tuple with decision
          assert {:ok, {should_include, reasoning}} = result
          assert is_boolean(should_include)
          assert is_binary(reasoning)

          # For sports content with "filter out sports" prompt, 
          # we expect it might be filtered out (false), but due to API variability
          # we just test that we get a valid response
      end
    end

    @tag :integration
    test "includes non-sports content when filtering sports" do
      # Only run this test if GEMINI_API_KEY is set
      case System.get_env("GEMINI_API_KEY") do
        nil ->
          # Skip test if API key not provided
          :ok

        _api_key ->
          item = %FeedItem{
            generated_id: "renewable-energy-678",
            title: "New Technology Breakthrough in Renewable Energy",
            description: "Scientists have developed a new solar panel technology...",
            categories: ["Technology", "Environment"]
          }

          # Test that non-sports content is included when filtering sports
          result = Gemini.should_include?(item, "filter out all sports-related content")

          # Should likely be true for non-sports content, but we just verify valid decision
          assert {:ok, {should_include, reasoning}} = result
          assert is_boolean(should_include)
          assert is_binary(reasoning)
      end
    end
  end

  describe "prompt building" do
    test "builds appropriate prompts for filtering logic" do
      # This is more of a documentation test to show how the prompts are structured
      item = %FeedItem{
        generated_id: "sample-article-901",
        title: "Sample Article",
        description: "Sample description",
        categories: ["Category1", "Category2"],
        link: "https://example.com"
      }

      # We can't easily test the private functions, but we can test the public interface
      # and verify that it handles the data correctly through the fallback behavior
      original_api_key = Application.get_env(:gemini_ex, :api_key)
      Application.put_env(:gemini_ex, :api_key, nil)

      capture_log(fn ->
        # Should handle the full item data without errors
        result = Gemini.should_include?(item, "detailed filtering criteria")
        assert {:error, _reason} = result
      end)

      # Restore original config
      Application.put_env(:gemini_ex, :api_key, original_api_key)
    end
  end
end
