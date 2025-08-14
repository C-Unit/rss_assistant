defmodule RssAssistant.AccountsTest do
  use RssAssistant.DataCase

  alias RssAssistant.Accounts

  import RssAssistant.AccountsFixtures
  import RssAssistant.FilteredFeedFixtures
  alias RssAssistant.Accounts.{User, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email_and_password("unknown@example.com", "hello world!")
    end

    test "does not return the user if the password is not valid" do
      user = user_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "invalid")
    end

    test "returns the user if the email and password are valid" do
      %{id: id} = user = user_fixture()

      assert %User{id: ^id} =
               Accounts.get_user_by_email_and_password(user.email, valid_user_password())
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires email and password to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{
               password: ["can't be blank"],
               email: ["can't be blank"]
             } = errors_on(changeset)
    end

    test "validates email and password when given" do
      {:error, changeset} = Accounts.register_user(%{email: "not valid", password: "not valid"})

      assert %{
               email: ["must have the @ sign and no spaces"],
               password: ["should be at least 12 character(s)"]
             } = errors_on(changeset)
    end

    test "validates maximum values for email and password for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_user(%{email: too_long, password: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the upper cased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users with a hashed password" do
      # Ensure Free plan exists
      free_plan_fixture()
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert is_binary(user.hashed_password)
      assert is_nil(user.confirmed_at)
      assert is_nil(user.password)
    end
  end

  describe "change_user_registration/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_registration(%User{})
      assert changeset.required == [:password, :email]
    end

    test "allows fields to be set" do
      email = unique_user_email()
      password = valid_user_password()

      changeset =
        Accounts.change_user_registration(
          %User{},
          valid_user_attributes(email: email, password: password)
        )

      assert changeset.valid?
      assert get_change(changeset, :email) == email
      assert get_change(changeset, :password) == password
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "change_user_email/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "apply_user_email/3" do
    setup do
      %{user: user_fixture()}
    end

    test "requires email to change", %{user: user} do
      {:error, changeset} = Accounts.apply_user_email(user, valid_user_password(), %{})
      assert %{email: ["did not change"]} = errors_on(changeset)
    end

    test "validates email", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum value for email for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.apply_user_email(user, valid_user_password(), %{email: too_long})

      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness", %{user: user} do
      %{email: email} = user_fixture()
      password = valid_user_password()

      {:error, changeset} = Accounts.apply_user_email(user, password, %{email: email})

      assert "has already been taken" in errors_on(changeset).email
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.apply_user_email(user, "invalid", %{email: unique_user_email()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "applies the email without persisting it", %{user: user} do
      email = unique_user_email()
      {:ok, user} = Accounts.apply_user_email(user, valid_user_password(), %{email: email})
      assert user.email == email
      assert Accounts.get_user!(user.id).email != email
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert Accounts.update_user_email(user, token) == :ok
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      assert changed_user.confirmed_at
      assert changed_user.confirmed_at != user.confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.update_user_email(user, token) == :error
      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "change_user_password/2" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_password(%User{})
      assert changeset.required == [:password]
    end

    test "allows fields to be set" do
      changeset =
        Accounts.change_user_password(%User{}, %{
          "password" => "new valid password"
        })

      assert changeset.valid?
      assert get_change(changeset, :password) == "new valid password"
      assert is_nil(get_change(changeset, :hashed_password))
    end
  end

  describe "update_user_password/3" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)

      {:error, changeset} =
        Accounts.update_user_password(user, valid_user_password(), %{password: too_long})

      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "validates current password", %{user: user} do
      {:error, changeset} =
        Accounts.update_user_password(user, "invalid", %{password: valid_user_password()})

      assert %{current_password: ["is not valid"]} = errors_on(changeset)
    end

    test "updates the password", %{user: user} do
      {:ok, user} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "new valid password"
        })

      assert is_nil(user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)

      {:ok, _} =
        Accounts.update_user_password(user, valid_user_password(), %{
          password: "new valid password"
        })

      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert session_user = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_user_confirmation_instructions/2" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "confirm"
    end
  end

  describe "confirm_user/1" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_confirmation_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "confirms the email with a valid token", %{user: user, token: token} do
      assert {:ok, confirmed_user} = Accounts.confirm_user(token)
      assert confirmed_user.confirmed_at
      assert confirmed_user.confirmed_at != user.confirmed_at
      assert Repo.get!(User, user.id).confirmed_at
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm with invalid token", %{user: user} do
      assert Accounts.confirm_user("oops") == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not confirm email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      assert Accounts.confirm_user(token) == :error
      refute Repo.get!(User, user.id).confirmed_at
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "deliver_user_reset_password_instructions/2" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "reset_password"
    end
  end

  describe "get_user_by_reset_password_token/1" do
    setup do
      user = user_fixture()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_reset_password_instructions(user, url)
        end)

      %{user: user, token: token}
    end

    test "returns the user with valid token", %{user: %{id: id}, token: token} do
      assert %User{id: ^id} = Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: id)
    end

    test "does not return the user with invalid token", %{user: user} do
      refute Accounts.get_user_by_reset_password_token("oops")
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not return the user if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])
      refute Accounts.get_user_by_reset_password_token(token)
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "reset_user_password/2" do
    setup do
      %{user: user_fixture()}
    end

    test "validates password", %{user: user} do
      {:error, changeset} =
        Accounts.reset_user_password(user, %{
          password: "not valid",
          password_confirmation: "another"
        })

      assert %{
               password: ["should be at least 12 character(s)"],
               password_confirmation: ["does not match password"]
             } = errors_on(changeset)
    end

    test "validates maximum values for password for security", %{user: user} do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.reset_user_password(user, %{password: too_long})
      assert "should be at most 72 character(s)" in errors_on(changeset).password
    end

    test "updates the password", %{user: user} do
      {:ok, updated_user} = Accounts.reset_user_password(user, %{password: "new valid password"})
      assert is_nil(updated_user.password)
      assert Accounts.get_user_by_email_and_password(user.email, "new valid password")
    end

    test "deletes all tokens for the given user", %{user: user} do
      _ = Accounts.generate_user_session_token(user)
      {:ok, _} = Accounts.reset_user_password(user, %{password: "new valid password"})
      refute Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "inspect/2 for the User module" do
    test "does not include password" do
      refute inspect(%User{password: "123456"}) =~ "password: \"123456\""
    end
  end

  describe "register_user/1 with plans" do
    setup do
      free_plan_fixture()
      %{}
    end

    test "assigns free plan by default" do
      {:ok, user} = Accounts.register_user(valid_user_attributes())
      user = Repo.preload(user, :plan)
      assert user.plan.name == "Free"
      assert user.plan.max_feeds == 0
    end
  end

  describe "plan management" do
    setup do
      free_plan = free_plan_fixture()
      pro_plan = pro_plan_fixture()
      %{free_plan: free_plan, pro_plan: pro_plan}
    end

    test "get_plan_by_name/1", %{free_plan: free_plan} do
      assert fetched_plan = Accounts.get_plan_by_name("Free")
      assert fetched_plan.id == free_plan.id
    end

    test "get_user_plan/1 with user struct", %{free_plan: _free_plan} do
      user = user_fixture()
      plan = Accounts.get_user_plan(user)
      assert plan.name == "Free"
    end

    test "get_user_plan/1 with user id", %{free_plan: _free_plan} do
      user = user_fixture()
      plan = Accounts.get_user_plan(user.id)
      assert plan.name == "Free"
    end

    test "change_user_plan/2 with user struct and plan name", %{pro_plan: pro_plan} do
      user = user_fixture()
      {:ok, updated_user} = Accounts.change_user_plan(user, "Pro")
      assert updated_user.plan_id == pro_plan.id
    end

    test "change_user_plan/2 with user struct and plan id", %{pro_plan: pro_plan} do
      user = user_fixture()
      {:ok, updated_user} = Accounts.change_user_plan(user, pro_plan.id)
      assert updated_user.plan_id == pro_plan.id
    end

    test "change_user_plan/2 with user id and plan name", %{pro_plan: pro_plan} do
      user = user_fixture()
      {:ok, updated_user} = Accounts.change_user_plan(user.id, "Pro")
      assert updated_user.plan_id == pro_plan.id
    end

    test "change_user_plan/2 with user id and plan id", %{pro_plan: pro_plan} do
      user = user_fixture()
      {:ok, updated_user} = Accounts.change_user_plan(user.id, pro_plan.id)
      assert updated_user.plan_id == pro_plan.id
    end

    test "can_create_feed?/1 returns false for free plan" do
      user = user_fixture()
      feed_status = Accounts.can_create_feed?(user)
      refute feed_status.can_create
      assert feed_status.plan.name == "Free"
      assert feed_status.current_count == 0
    end

    test "can_create_feed?/1 returns true for pro plan with no feeds", %{pro_plan: pro_plan} do
      user = user_fixture()
      {:ok, updated_user} = Accounts.change_user_plan(user, pro_plan.id)
      user = Repo.preload(updated_user, :plan, force: true)
      feed_status = Accounts.can_create_feed?(user)
      assert feed_status.can_create
      assert feed_status.plan.name == "Pro"
      assert feed_status.current_count == 0
    end

    test "can_create_feed?/1 returns false for pro plan at limit", %{pro_plan: pro_plan} do
      user = user_fixture()
      {:ok, updated_user} = Accounts.change_user_plan(user, pro_plan.id)

      # Create feeds up to the limit
      for _i <- 1..100 do
        filtered_feed_fixture(%{user_id: updated_user.id})
      end

      user = Repo.preload(updated_user, :plan, force: true)
      feed_status = Accounts.can_create_feed?(user)
      refute feed_status.can_create
      assert feed_status.plan.name == "Pro"
      assert feed_status.current_count == 100
    end

    test "get_user_feed_count/1 with user struct" do
      user = user_fixture()
      assert Accounts.get_user_feed_count(user) == 0

      filtered_feed_fixture(%{user_id: user.id})
      filtered_feed_fixture(%{user_id: user.id})

      assert Accounts.get_user_feed_count(user) == 2
    end

    test "get_user_feed_count/1 with user id" do
      user = user_fixture()
      assert Accounts.get_user_feed_count(user.id) == 0

      filtered_feed_fixture(%{user_id: user.id})

      assert Accounts.get_user_feed_count(user.id) == 1
    end

    test "get_user_feeds/1 with user struct" do
      user = user_fixture()
      feed1 = filtered_feed_fixture(%{user_id: user.id})
      feed2 = filtered_feed_fixture(%{user_id: user.id})

      feeds = Accounts.get_user_feeds(user)
      feed_ids = Enum.map(feeds, & &1.id)

      assert length(feeds) == 2
      assert feed1.id in feed_ids
      assert feed2.id in feed_ids
    end

    test "get_user_feeds/1 with user id" do
      user = user_fixture()
      feed = filtered_feed_fixture(%{user_id: user.id})

      feeds = Accounts.get_user_feeds(user.id)

      assert length(feeds) == 1
      assert hd(feeds).id == feed.id
    end

    test "get_user_feeds/1 orders by most recent" do
      user = user_fixture()

      # Create feeds with explicit timestamps
      older_time = ~U[2023-01-01 10:00:00Z]
      newer_time = ~U[2023-01-01 11:00:00Z]

      _feed1 =
        %RssAssistant.FilteredFeed{}
        |> RssAssistant.FilteredFeed.changeset(%{
          user_id: user.id,
          url: "https://example.com/old.xml",
          prompt: "Old feed"
        })
        |> Ecto.Changeset.put_change(:inserted_at, older_time)
        |> Repo.insert!()

      feed2 =
        %RssAssistant.FilteredFeed{}
        |> RssAssistant.FilteredFeed.changeset(%{
          user_id: user.id,
          url: "https://example.com/new.xml",
          prompt: "New feed"
        })
        |> Ecto.Changeset.put_change(:inserted_at, newer_time)
        |> Repo.insert!()

      feeds = Accounts.get_user_feeds(user)

      assert length(feeds) == 2
      # Most recent first
      assert hd(feeds).id == feed2.id
    end

    test "list_plans/0" do
      plans = Accounts.list_plans()
      plan_names = Enum.map(plans, & &1.name)

      assert "Free" in plan_names
      assert "Pro" in plan_names
    end

    test "get_user_filtered_feed_by_slug/2 with user struct" do
      user = user_fixture()
      feed = filtered_feed_fixture(%{user_id: user.id})

      fetched_feed = Accounts.get_user_filtered_feed_by_slug(user, feed.slug)
      assert fetched_feed.id == feed.id
    end

    test "get_user_filtered_feed_by_slug/2 with user id" do
      user = user_fixture()
      feed = filtered_feed_fixture(%{user_id: user.id})

      fetched_feed = Accounts.get_user_filtered_feed_by_slug(user.id, feed.slug)
      assert fetched_feed.id == feed.id
    end

    test "get_user_filtered_feed_by_slug/2 raises for nonexistent feed" do
      user = user_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user_filtered_feed_by_slug(user, "nonexistent")
      end
    end

    test "get_user_filtered_feed_by_slug/2 raises for other user's feed" do
      user1 = user_fixture()
      user2 = user_fixture()
      feed = filtered_feed_fixture(%{user_id: user1.id})

      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user_filtered_feed_by_slug(user2, feed.slug)
      end
    end
  end
end
