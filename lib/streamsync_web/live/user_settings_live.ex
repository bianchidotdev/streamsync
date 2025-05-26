defmodule StreamsyncWeb.UserSettingsLive do
  require Logger
  use StreamsyncWeb, :live_view

  alias Streamsync.Accounts

  def render(assigns) do
    ~H"""
    <.header class="text-center">
      Account Settings
      <:subtitle>Manage your email address and account settings</:subtitle>
    </.header>

    <div class="space-y-6">
      <h3 class="text-lg font-medium leading-6 text-gray-900">Connected Providers</h3>
      <ul role="list" class="divide-y divide-gray-200">
        <%= for connection <- @provider_connections do %>
          <li class="py-4 flex items-center justify-between">
            <div>
              <p class="text-sm font-medium text-gray-900">
                Provider: {connection.provider}
              </p>
              <p class="text-sm text-gray-500">
                Email: {connection.provider_email}
              </p>
            </div>
            <div class="flex items-center space-x-4">
              <p class="text-sm text-gray-500">
                UID: {connection.provider_uid}
              </p>
              <%= if length(@provider_connections) > 1 do %>
                <button
                  phx-click="delete_provider_connection"
                  phx-value-id={connection.id}
                  class="text-red-600 hover:text-red-900"
                  data-confirm="Are you sure you want to disconnect this provider?"
                >
                  <.icon name="hero-trash" class="h-5 w-5" />
                </button>
              <% end %>
            </div>
          </li>
        <% end %>
      </ul>

      <%= if @unconnected_providers != [] do %>
        <div class="mt-6">
          <h3 class="text-lg font-medium leading-6 text-gray-900">Connect Additional Providers</h3>
          <div class="mt-4 space-y-4">
            <%= for provider <- @unconnected_providers do %>
              <.link
                href={~p"/auth/#{provider}"}
                class="inline-flex items-center justify-center w-full px-4 py-2 text-sm font-semibold text-white bg-gray-900 border border-transparent rounded-md shadow-sm hover:bg-gray-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500"
              >
                Connect {String.capitalize(provider)}
              </.link>
            <% end %>
          </div>
        </div>
      <% end %>
    </div>

    <div class="space-y-12 divide-y">
      <div>
        <.simple_form
          for={@email_form}
          id="email_form"
          phx-submit="update_email"
          phx-change="validate_email"
        >
          <.input field={@email_form[:email]} type="email" label="Email" required />
          <:actions>
            <.button phx-disable-with="Changing...">Change Email</.button>
          </:actions>
        </.simple_form>
      </div>
    </div>
    """
  end

  def mount(%{"token" => token}, _session, socket) do
    socket =
      case Accounts.update_user_email(socket.assigns.current_user, token) do
        :ok ->
          put_flash(socket, :info, "Email changed successfully.")

        :error ->
          put_flash(socket, :error, "Email change link is invalid or it has expired.")
      end

    {:ok, push_navigate(socket, to: ~p"/users/settings")}
  end

  def mount(_params, _session, socket) do
    user = Streamsync.Accounts.get_user_with_provider_connections(socket.assigns.current_user.id)
    email_changeset = Accounts.change_user_email(user)
    unconnected_providers = Streamsync.Accounts.get_unconnected_providers(user)

    socket =
      socket
      |> assign(:current_email, user.email)
      |> assign(:email_form, to_form(email_changeset))
      |> assign(:trigger_submit, false)
      |> assign(:provider_connections, user.provider_connections)
      |> assign(:unconnected_providers, unconnected_providers)

    {:ok, socket}
  end

  def handle_event("validate_email", params, socket) do
    %{"user" => user_params} = params

    email_form =
      socket.assigns.current_user
      |> Accounts.change_user_email(user_params)
      |> Map.put(:action, :validate)
      |> to_form()

    {:noreply, assign(socket, email_form: email_form)}
  end

  def handle_event("update_email", params, socket) do
    %{"user" => user_params} = params
    user = socket.assigns.current_user

    case Accounts.apply_user_email(user, user_params) do
      {:ok, applied_user} ->
        Accounts.deliver_user_update_email_instructions(
          applied_user,
          user.email,
          &url(~p"/users/settings/confirm_email/#{&1}")
        )

        info = "A link to confirm your email change has been sent to the new address."
        {:noreply, socket |> put_flash(:info, info)}

      {:error, changeset} ->
        {:noreply, assign(socket, :email_form, to_form(Map.put(changeset, :action, :insert)))}
    end
  end

  def handle_event("delete_provider_connection", %{"id" => connection_id}, socket) do
    user_id = socket.assigns.current_user.id

    case Accounts.delete_user_provider_connection(String.to_integer(connection_id), user_id) do
      {:ok, _connection} ->
        user = Streamsync.Accounts.get_user_with_provider_connections(user_id)
        unconnected_providers = Streamsync.Accounts.get_unconnected_providers(user)

        socket =
          socket
          |> put_flash(:info, "Provider connection successfully removed.")
          |> assign(:provider_connections, user.provider_connections)
          |> assign(:unconnected_providers, unconnected_providers)

        {:noreply, socket}

      {:error, :last_connection} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Cannot remove your last provider connection. You would be locked out of your account."
         )}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Provider connection not found.")}

      {:error, reason} ->
        Logger.error(
          "Failed to remove provider connection for user #{user_id} with connection ID #{connection_id}",
          error: inspect(reason)
        )

        {:noreply, put_flash(socket, :error, "Failed to remove provider connection.")}
    end
  end
end
