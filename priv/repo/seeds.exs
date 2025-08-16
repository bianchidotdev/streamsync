# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Streamsync.Repo.insert!(%Streamsync.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Streamsync.Accounts
alias Streamsync.Accounts.UserProviderConnection
alias Streamsync.Repo

# Find or create a test user
user =
  case Accounts.get_user_by_email("test@example.com") do
    nil ->
      user_attrs = %{email: "test@example.com"}
      {:ok, user} = Accounts.register_user(user_attrs)
      IO.puts("Created test user: #{user.email} (ID: #{user.id})")
      user

    existing_user ->
      IO.puts("Found existing test user: #{existing_user.email} (ID: #{existing_user.id})")
      existing_user
  end

# Find or create Spotify provider connection for the test user
spotify_connection =
  case Repo.get_by(UserProviderConnection, user_id: user.id, provider: "spotify") do
    nil ->
      spotify_connection_attrs = %{
        user_id: user.id,
        provider: "spotify",
        provider_email: "test@example.com",
        provider_uid: "spotify_test_123",
        access_token: "mock_spotify_token",
        refresh_token: "mock_refresh_token"
      }

      {:ok, connection} =
        %UserProviderConnection{}
        |> UserProviderConnection.changeset(spotify_connection_attrs)
        |> Repo.insert()

      IO.puts("Created Spotify connection for user #{connection.user_id}")
      connection

    existing_connection ->
      IO.puts("Found existing Spotify connection for user #{existing_connection.user_id}")
      existing_connection
  end

# Find or create Tidal provider connection for the test user
tidal_connection =
  case Repo.get_by(UserProviderConnection, user_id: user.id, provider: "tidal") do
    nil ->
      tidal_connection_attrs = %{
        user_id: user.id,
        provider: "tidal",
        provider_email: "test@example.com",
        provider_uid: "tidal_test_456",
        access_token: "mock_tidal_token",
        refresh_token: "mock_tidal_refresh_token"
      }

      {:ok, connection} =
        %UserProviderConnection{}
        |> UserProviderConnection.changeset(tidal_connection_attrs)
        |> Repo.insert()

      IO.puts("Created Tidal connection for user #{connection.user_id}")
      connection

    existing_connection ->
      IO.puts("Found existing Tidal connection for user #{existing_connection.user_id}")
      existing_connection
  end

IO.puts("Test data setup complete!")
