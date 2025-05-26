defmodule StreamsyncWeb.AuthController do
  use StreamsyncWeb, :controller
  require Logger
  plug Ueberauth

  def callback(%{assigns: %{ueberauth_failure: %Ueberauth.Failure{}}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate")
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_auth: %Ueberauth.Auth{} = _auth}} = conn, params) do
    if conn.assigns[:current_user] do
      handle_new_connection_request(conn, params)
    else
      handle_login_request(conn, params)
    end
  end

  def handle_login_request(
        %{assigns: %{ueberauth_auth: %Ueberauth.Auth{} = auth}} = conn,
        _params
      ) do
    provider = auth.provider
    Logger.info("Login for provider #{provider} with UID #{auth.uid}")

    case Streamsync.Accounts.handle_oauth_login(provider, auth) do
      {:ok, user} ->
        conn
        |> StreamsyncWeb.UserAuth.log_in_user(user)
        |> redirect(to: "/")

      {:error, %Ecto.Changeset{errors: [email: {"has already been taken", _details}]}} ->
        conn
        |> put_flash(
          :error,
          "An account with this email already exists. Please log in using the original provider."
        )
        |> redirect(to: "/")

      {:error, error} ->
        Logger.error("Error during OAuth login: #{inspect(error)}")

        conn
        |> put_flash(:error, "Authentication failed")
        |> redirect(to: "/")
    end
  end

  def handle_new_connection_request(
        %{assigns: %{ueberauth_auth: %Ueberauth.Auth{} = auth}} = conn,
        _params
      ) do
    provider = auth.provider
    user = conn.assigns[:current_user]

    Logger.info("User #{user.id} is already logged in, connecting new provider #{provider}")

    case Streamsync.Accounts.handle_new_oauth_connection(provider, auth, user) do
      {:ok, _} ->
        conn
        |> put_flash(:info, "Successfully connected #{provider} account")
        |> redirect(to: "/")

      {:error, error} ->
        Logger.error("Error connecting OAuth account: #{inspect(error)}")

        conn
        |> put_flash(:error, "Failed to connect account")
        |> redirect(to: "/")
    end
  end
end
