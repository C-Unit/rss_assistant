# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     RssAssistant.Repo.insert!(%RssAssistant.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias RssAssistant.Repo
alias RssAssistant.Accounts.Plan

# Create default plans
free_plan = Repo.insert!(%Plan{
  name: "Free",
  max_feeds: 0,
  price: Decimal.new("0.00")
})

_pro_plan = Repo.insert!(%Plan{
  name: "Pro",
  max_feeds: 100,
  price: Decimal.new("99.99")
})

IO.puts("Created default plans with IDs: Free (#{free_plan.id})")
