ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(RssAssistant.Repo, :manual)

# Define mocks
Mox.defmock(RssAssistant.Filter.Mock, for: RssAssistant.Filter)
