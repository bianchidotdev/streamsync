defmodule StreamsyncWeb.UserSessionController do
  use StreamsyncWeb, :controller

  alias StreamsyncWeb.UserAuth

  # TODO: do not know if these are meaningful in the context
  # of oauth driven auth flows
  # def create(conn, %{"_action" => "registered"} = params) do
  #   create(conn, params, "Account created successfully!")
  # end

  # def create(conn, params) do
  #   create(conn, params, "Welcome back!")
  # end

  # defp create(conn, %{"user" => user_params}, info) do
  #   %{"email" => email} = user_params

  #   if user = Accounts.get_user_by_email_and_password(email, password) do
  #     conn
  #     |> put_flash(:info, info)
  #     |> UserAuth.log_in_user(user, user_params)
  #   else
  #     # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
  #     conn
  #     |> put_flash(:error, "Invalid email or password")
  #     |> put_flash(:email, String.slice(email, 0, 160))
  #     |> redirect(to: ~p"/users/log_in")
  #   end
  # end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
