defmodule Streamsync.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Streamsync.Accounts.UserProviderConnection
  alias Streamsync.Repo

  alias Streamsync.Accounts.{User, UserToken, UserNotifier}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## Oauth fetch or create

  @doc """
    Fetches or creates a user.
    For the OAuth case, there is no previous registration step.
    The user may, or may not exist in the database at the time of sign-in.
  """

  # NOTE(bianchi): this shouldn't be used anymore since we require a provider
  # connection and lookup by that
  # def fetch_or_create_user(attrs) do
  #   case get_user_by_email(attrs.email) do
  #     %User{} = user ->
  #       {:ok, user}

  #     _ ->
  #       %User{}
  #       |> User.registration_changeset(attrs)
  #       |> Repo.insert()
  #   end
  # end

  def get_user_with_provider_connections(user_id) do
    Repo.get(User, user_id)
    |> Repo.preload(:provider_connections)
  end

  def handle_oauth_login(provider, %Ueberauth.Auth{} = auth) do
    provider_string = Atom.to_string(provider)
    provider_uid = auth.uid
    provider_email = auth.info.email

    parse_expires_at =
      case auth.credentials.expires_at do
        nil -> nil
        expires_at -> DateTime.from_unix!(expires_at, :second)
      end

    connection =
      Repo.get_by(UserProviderConnection, provider: provider_string, provider_uid: provider_uid)

    case connection do
      # If a connection exists, update it with the most recent creds
      %UserProviderConnection{} = connection ->
        Repo.transaction(fn ->
          with {:ok, updated_connection} <-
                 connection
                 |> UserProviderConnection.changeset(%{
                   access_token: auth.credentials.token,
                   refresh_token: auth.credentials.refresh_token,
                   expires_at: parse_expires_at,
                   provider_email: provider_email
                 })
                 |> Repo.update(),
               %User{} = user <- Repo.get(User, updated_connection.user_id) do
            user
          else
            nil -> {:error, :user_not_found}
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

      # If no connection exists, create a new user and connection
      nil ->
        Repo.transaction(fn ->
          with {:ok, user} <-
                 %User{}
                 |> User.registration_changeset(%{email: provider_email})
                 |> Repo.insert(),
               {:ok, _connection} <-
                 %UserProviderConnection{}
                 |> UserProviderConnection.changeset(%{
                   provider: provider_string,
                   provider_email: provider_email,
                   provider_uid: provider_uid,
                   access_token: auth.credentials.token,
                   refresh_token: auth.credentials.refresh_token,
                   expires_at: parse_expires_at,
                   user_id: user.id
                 })
                 |> Repo.insert() do
            user
          else
            {:error, reason} -> Repo.rollback(reason)
          end
        end)
    end
  end

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, validate_email: false)
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  # TODO: this is probably meaningless in a passwordless world
  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}

      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, attrs) do
    user
    |> User.email_changeset(attrs)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(user_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, [context]))
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm_email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @doc ~S"""
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &url(~p"/users/confirm/#{&1}"))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &url(~p"/users/confirm/#{&1}"))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end
end
