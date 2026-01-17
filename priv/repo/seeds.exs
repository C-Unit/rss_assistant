alias RssAssistant.Repo
alias RssAssistant.Accounts.Plan

plans = [
  %{
    name: "Free",
    max_feeds: 0,
    price: Decimal.new("0.00"),
    stripe_price_id: nil,
    stripe_product_id: nil
  },
  %{
    name: "Pro",
    max_feeds: 100,
    price: Decimal.new("99.99"),
    stripe_price_id: System.get_env("STRIPE_PRO_PRICE_ID"),
    stripe_product_id: System.get_env("STRIPE_PRO_PRODUCT_ID")
  }
]

Enum.each(plans, fn plan_data ->
  # 1. Attempt to find the plan by name
  case Repo.get_by(Plan, name: plan_data.name) do
    nil ->
      # 2. If it doesn't exist, insert it
      %Plan{}
      |> Plan.changeset(plan_data)
      |> Repo.insert!()

      IO.puts("Inserted new plan: #{plan_data.name}")

    existing_plan ->
      # 3. If it does exist, update it (syncs the script values to the DB)
      existing_plan
      |> Plan.changeset(plan_data)
      |> Repo.update!()

      IO.puts("Updated existing plan: #{plan_data.name}")
  end
end)
