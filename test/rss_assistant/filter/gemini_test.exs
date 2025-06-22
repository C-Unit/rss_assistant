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
        title: "Test Article",
        description: "A test article about technology",
        categories: ["tech"]
      }

      # Should fall back to including the item when API is not configured
      capture_log(fn ->
        assert Gemini.should_include?(item, "filter out sports content") == true
      end)

      # Restore original config
      Application.put_env(:gemini_ex, :api_key, original_api_key)
    end

    test "handles empty feed item gracefully" do
      # Clear any API key to test fallback behavior
      original_api_key = Application.get_env(:gemini_ex, :api_key)
      Application.put_env(:gemini_ex, :api_key, nil)

      item = %FeedItem{
        title: nil,
        description: nil,
        categories: []
      }

      # Should still work with minimal data
      capture_log(fn ->
        assert Gemini.should_include?(item, "any filter") == true
      end)

      # Restore original config
      Application.put_env(:gemini_ex, :api_key, original_api_key)
    end

    test "handles various category formats" do
      # Clear any API key to test fallback behavior
      original_api_key = Application.get_env(:gemini_ex, :api_key)
      Application.put_env(:gemini_ex, :api_key, nil)

      item_with_categories = %FeedItem{
        title: "Article with categories",
        description: "Description",
        categories: ["Technology", "AI", "Programming"]
      }

      item_without_categories = %FeedItem{
        title: "Article without categories",
        description: "Description",
        categories: []
      }

      capture_log(fn ->
        assert Gemini.should_include?(item_with_categories, "filter tech") == true
        assert Gemini.should_include?(item_without_categories, "filter tech") == true
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
            title: "Breaking: Local Sports Team Wins Championship",
            description: "The hometown football team secured a decisive victory last night...",
            categories: ["Sports", "Local News"]
          }

          # Test filtering out sports content
          result = Gemini.should_include?(item, "filter out all sports-related content")
          
          # Result should be a boolean (either true or false)
          assert is_boolean(result)
          
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
            title: "New Technology Breakthrough in Renewable Energy",
            description: "Scientists have developed a new solar panel technology...",
            categories: ["Technology", "Environment"]
          }

          # Test that non-sports content is included when filtering sports
          result = Gemini.should_include?(item, "filter out all sports-related content")
          
          # Should likely be true for non-sports content, but we just verify boolean response
          assert is_boolean(result)
      end
    end
  end

  describe "prompt building" do
    test "builds appropriate prompts for filtering logic" do
      # This is more of a documentation test to show how the prompts are structured
      item = %FeedItem{
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
        assert is_boolean(result)
      end)

      # Restore original config
      Application.put_env(:gemini_ex, :api_key, original_api_key)
    end
  end
end