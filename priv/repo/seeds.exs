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

upsert_plan = fn attrs ->
  case Repo.get_by(Plan, name: attrs.name) do
    nil ->
      %Plan{}
      |> Plan.changeset(attrs)
      |> Repo.insert!()

    existing ->
      existing
      |> Plan.changeset(attrs)
      |> Repo.update!()
  end
end

# Create or update default plans
free_plan =
  upsert_plan.(%{
    name: "Free",
    max_feeds: 0,
    price: Decimal.new("0.00")
  })

pro_plan =
  upsert_plan.(%{
    name: "Pro",
    max_feeds: 100,
    price: Decimal.new("99.99"),
    stripe_price_id: System.get_env("STRIPE_PRO_PRICE_ID")
  })

IO.puts("Upserted plans: Free (#{free_plan.id}), Pro (#{pro_plan.id})")
