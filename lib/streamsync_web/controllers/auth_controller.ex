defmodule StreamsyncWeb.AuthController do
  use StreamsyncWeb, :controller
  require Logger
  plug Ueberauth

  def callback(%{assigns: %{ueberauth_failure: %Ueberauth.Failure{}}} = conn, _params) do
    conn
    |> put_flash(:error, "Failed to authenticate")
    |> redirect(to: ~p"/")
  end

  def callback(%{assigns: %{ueberauth_auth: %Ueberauth.Auth{} = auth}} = conn, _params) do
    dbg()
    email = auth.info.email
    provider = auth.provider
    Logger.info("Login for #{provider} with email: #{email}")

    case Streamsync.Accounts.handle_oauth_login(provider, auth) do
      {:ok, user} ->
        StreamsyncWeb.UserAuth.log_in_user(conn, user)

      {:error, %Ecto.Changeset{errors: [email: {"has already been taken", _details}]}} ->
        conn
        |> put_flash(
          :error,
          "An account with this email already exists. Please log in using the original provider."
        )
        |> redirect(to: "/")

      # error #=> {:error,
      #  #Ecto.Changeset<
      #    action: :insert,
      #    changes: %{email: "michael@bianchi.dev"},
      #    errors: [
      #      email: {"has already been taken",
      #       [validation: :unsafe_unique, fields: [:email]]}
      #    ],
      #    data: #Streamsync.Accounts.User<>,
      #    valid?: false,
      #    ...
      #  >}
      error ->
        conn
        |> put_flash(:error, "Authentication failed")
        |> redirect(to: "/")
    end
  end
end
