# Exclude Gemini API tests if GEMINI_API_KEY is not set
exclude_opts =
  if is_nil(System.get_env("GEMINI_API_KEY")) do
    IO.warn("Excluding Gemini API tests: GEMINI_API_KEY environment variable not set")
    [exclude: [:gemini_api]]
  else
    []
  end

ExUnit.start(exclude_opts)
Ecto.Adapters.SQL.Sandbox.mode(RssAssistant.Repo, :manual)

# Define mocks
Mox.defmock(RssAssistant.Filter.Mock, for: RssAssistant.Filter)
