import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :rss_assistant, RssAssistant.Repo,
  username: System.get_env("USER"),
  hostname: "localhost",
  database: "rss_assistant_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :rss_assistant, RssAssistantWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "a8oB2/wn1axlm/DtumMgBRb2GEpKk9w7J/sJpAHTtAy1+c2DLrVfSJa/KMP5lomL",
  server: false

# In test we don't send emails
config :rss_assistant, RssAssistant.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Use mock filter implementation for testing
config :rss_assistant, filter_impl: RssAssistant.Filter.Mock
