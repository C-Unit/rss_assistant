# Build exclusion list based on missing environment variables
excludes =
  []
  |> then(fn excludes ->
    if is_nil(System.get_env("OPENROUTER_API_KEY")) do
      IO.warn("Excluding OpenRouter API tests: OPENROUTER_API_KEY environment variable not set")
      [:openrouter_api | excludes]
    else
      excludes
    end
  end)
  |> then(fn excludes ->
    if is_nil(System.get_env("STRIPE_SECRET_KEY")) do
      IO.warn("Excluding Stripe API tests: STRIPE_SECRET_KEY environment variable not set")
      [:stripe_api | excludes]
    else
      excludes
    end
  end)

ExUnit.start(exclude: excludes)
Ecto.Adapters.SQL.Sandbox.mode(RssAssistant.Repo, :manual)

# Define mocks
Mox.defmock(RssAssistant.Filter.Mock, for: RssAssistant.Filter)
