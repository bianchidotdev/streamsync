defmodule StreamsyncWeb.UserLoginLive do
  use StreamsyncWeb, :live_view

  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <.header class="text-center">
        Log in to account
      </.header>

      <div class="mb-6 text-center text-sm text-gray-600">
        Log in with your favorite music service. You can connect additional services later.
      </div>

      <.simple_form for={@form} id="login_form" action={~p"/users/log_in"} phx-update="ignore">
        <div class="space-y-4">
          <.link
            href={~p"/auth/spotify"}
            class="inline-flex items-center justify-center w-full px-4 py-2 text-sm font-semibold text-white bg-gray-900 border border-transparent rounded-md shadow-sm hover:bg-gray-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500"
          >
            Continue with Spotify
          </.link>
          <.link
            href={~p"/auth/tidal"}
            class="inline-flex items-center justify-center w-full px-4 py-2 text-sm font-semibold text-white bg-gray-900 border border-transparent rounded-md shadow-sm hover:bg-gray-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-gray-500"
          >
            Continue with Tidal
          </.link>
        </div>
      </.simple_form>
    </div>
    """
  end

  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    form = to_form(%{"email" => email}, as: "user")
    {:ok, assign(socket, form: form), temporary_assigns: [form: form]}
  end
end
