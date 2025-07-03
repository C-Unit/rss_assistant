defmodule RssAssistant.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `RssAssistant.Accounts` context.
  """

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password()
    })
  end

  def user_fixture(attrs \\ %{}) do
    # Ensure Free plan exists for registration
    unless RssAssistant.Repo.get_by(RssAssistant.Accounts.Plan, name: "Free") do
      free_plan_fixture()
    end

    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> RssAssistant.Accounts.register_user()

    user
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def valid_plan_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      name: "Test Plan",
      max_feeds: 5,
      price: Decimal.new("9.99")
    })
  end

  def plan_fixture(attrs \\ %{}) do
    %RssAssistant.Accounts.Plan{}
    |> RssAssistant.Accounts.Plan.changeset(valid_plan_attributes(attrs))
    |> RssAssistant.Repo.insert!()
  end

  def free_plan_fixture do
    plan_fixture(%{name: "Free", max_feeds: 0, price: Decimal.new("0.00")})
  end

  def pro_plan_fixture do
    plan_fixture(%{name: "Pro", max_feeds: 100, price: Decimal.new("99.99")})
  end
end
