defmodule RssAssistant.Repo do
  use Ecto.Repo,
    otp_app: :rss_assistant,
    adapter: Ecto.Adapters.Postgres
end
