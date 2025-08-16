defmodule StreamsyncWeb.SyncSongsLive.Index do
  alias Phoenix.LiveView.AsyncResult
  use StreamsyncWeb, :live_view

  alias Streamsync.Spotify
  alias Streamsync.Tidal
  alias Streamsync.Sync

  @impl true
  def mount(_params, _session, socket) do
    # Get available providers for this user
    available_providers = get_available_providers(socket.assigns.current_user)

    {:ok,
     socket
     |> assign(:page_title, "Music Sync")
     |> assign(:available_providers, available_providers)
     |> assign(:from_provider, nil)
     |> assign(:to_provider, nil)
     |> assign(:active_tab, "saved_songs")
     |> assign(:songs, %AsyncResult{loading: false, ok?: true})
     |> assign(:playlists, %AsyncResult{loading: false, ok?: true})
     |> assign(:albums, %AsyncResult{loading: false, ok?: true})
     |> assign(:artists, %AsyncResult{loading: false, ok?: true})
     |> assign(:selected_items, [])
     |> assign(:loading, false)
     |> assign(:error_message, nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Music Sync")
  end

  @impl true
  def handle_event("select_from_provider", %{"provider" => provider}, socket) do
    user = socket.assigns.current_user
    active_tab = socket.assigns.active_tab

    {:noreply,
     socket
     |> assign(:from_provider, provider)
     |> assign(:error_message, nil)
     |> load_content_for_tab(active_tab, provider, user)
     |> assign(:selected_items, [])}
  end

  @impl true
  def handle_event("select_to_provider", %{"provider" => provider}, socket) do
    {:noreply,
     socket
     |> assign(:to_provider, provider)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    user = socket.assigns.current_user
    provider = socket.assigns.from_provider

    socket =
      socket
      |> assign(:active_tab, tab)
      |> assign(:selected_items, [])

    socket =
      if provider do
        load_content_for_tab(socket, tab, provider, user)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_select", %{"id" => item_id}, socket) do
    selected_items = socket.assigns.selected_items

    updated_selected_items =
      if item_id in selected_items do
        List.delete(selected_items, item_id)
      else
        [item_id | selected_items]
      end

    {:noreply, assign(socket, :selected_items, updated_selected_items)}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    items = get_current_tab_items(socket)
    selected_items = socket.assigns.selected_items

    # If all items are selected, unselect all. Otherwise, select all.
    updated_selected_items =
      if length(selected_items) == length(items) do
        []
      else
        Enum.map(items, & &1.id)
      end

    {:noreply, assign(socket, :selected_items, updated_selected_items)}
  end

  @impl true
  def handle_event("create_sync_job", _params, socket) do
    %{
      from_provider: from_provider,
      to_provider: to_provider,
      selected_items: selected_items,
      current_user: current_user,
      active_tab: active_tab
    } = socket.assigns

    case Sync.create_sync_job(current_user, %{
           from_provider: from_provider,
           to_provider: to_provider,
           sync_type: active_tab,
           source_provider_ids: selected_items
         }) do
      {:ok, sync_job} ->
        item_type = get_item_type_label(active_tab)

        {:noreply,
         socket
         |> put_flash(
           :info,
           "Sync job ##{sync_job.id} created! Syncing #{length(selected_items)} #{item_type} from #{from_provider} to #{to_provider}."
         )
         |> push_navigate(to: ~p"/sync")}

      {:error, changeset} ->
        error_message =
          changeset.errors
          |> Enum.map(fn {field, {msg, _}} -> "#{field}: #{msg}" end)
          |> Enum.join(", ")

        {:noreply,
         socket
         |> put_flash(:error, "Failed to create sync job: #{error_message}")}
    end
  end

  # Helper functions
  defp load_content_for_tab(socket, tab, provider, user) do
    case tab do
      "saved_songs" ->
        assign_async(socket, :songs, fn ->
          case fetch_saved_tracks(provider, user) do
            {:ok, songs} ->
              {:ok, %{songs: songs}}

            {:error, reason} ->
              {:error, reason}
          end
        end)

      "playlists" ->
        assign_async(socket, :playlists, fn ->
          case fetch_playlists(provider, user) do
            {:ok, playlists} ->
              {:ok, %{playlists: playlists}}

            {:error, reason} ->
              {:error, reason}
          end
        end)

      "albums" ->
        assign_async(socket, :albums, fn ->
          case fetch_albums(provider, user) do
            {:ok, albums} -> {:ok, %{albums: albums}}
            {:error, reason} -> {:error, reason}
          end
        end)

      "artists" ->
        assign_async(socket, :artists, fn ->
          case fetch_artists(provider, user) do
            {:ok, artists} -> {:ok, %{artists: artists}}
            {:error, reason} -> {:error, reason}
          end
        end)
    end
  end

  defp get_current_tab_items(socket) do
    case socket.assigns.active_tab do
      "saved_songs" ->
        case socket.assigns.songs.result do
          songs -> songs
          _ -> []
        end

      "playlists" ->
        case socket.assigns.playlists.result do
          playlists -> playlists
          _ -> []
        end

      "albums" ->
        case socket.assigns.albums.result do
          albums -> albums
          _ -> []
        end

      "artists" ->
        case socket.assigns.artists.result do
          artists -> artists
          _ -> []
        end
    end
  end

  defp convert_to_song_ids(socket, selected_items, "saved_songs"), do: selected_items

  defp convert_to_song_ids(socket, selected_items, _tab) do
    # For playlists, albums, artists - we'd need to fetch their tracks
    # For now, we'll just return the IDs as placeholders
    selected_items
  end

  defp get_item_type_label("saved_songs"), do: "songs"
  defp get_item_type_label("playlists"), do: "playlists"
  defp get_item_type_label("albums"), do: "albums"
  defp get_item_type_label("artists"), do: "artists"

  # Check which providers the user has connected
  defp get_available_providers(user) do
    # Get actual connected providers for this user
    _connected_providers =
      Streamsync.Accounts.get_user_with_provider_connections(user.id)
      |> case do
        %{provider_connections: connections} -> Enum.map(connections, & &1.provider)
        _ -> []
      end

    # Add all supported providers to the list
    all_providers = ["spotify", "tidal"]

    # For now, show all providers regardless of connection status
    # In a real app, you might want to filter to only connected providers
    # or show connection status in the UI
    all_providers
  end

  # Fetch different types of content from providers
  defp fetch_saved_tracks(provider, user) do
    {:ok, []}
    # case provider do
    #   "spotify" -> Spotify.get_saved_tracks(user, all_pages: true)
    #   "tidal" -> Tidal.get_saved_tracks(user)
    #   _ -> {:error, "Unknown provider: #{provider}"}
    # end
    # |> handle_api_response()
  end

  defp fetch_playlists(provider, user) do
    case provider do
      "spotify" -> Spotify.get_playlists(user, all_pages: true)
      "tidal" -> Tidal.get_playlists(user)
      _ -> {:error, "Unknown provider: #{provider}"}
    end
    |> handle_api_response()
  end

  defp fetch_albums(provider, user) do
    # For now, return empty list as albums API isn't implemented yet
    {:ok, []}
  end

  defp fetch_artists(provider, user) do
    # For now, return empty list as artists API isn't implemented yet
    {:ok, []}
  end

  defp handle_api_response({:ok, data}), do: {:ok, data}

  defp handle_api_response({:error, :no_connection}) do
    {:error, "No connection found. Please connect your account first."}
  end

  defp handle_api_response({:error, :unauthorized}) do
    {:error, "Authorization expired. Please reconnect your account."}
  end

  defp handle_api_response({:error, {:rate_limited, retry_after}}) do
    {:error, "API rate limit exceeded. Please try again in #{retry_after} seconds."}
  end

  defp handle_api_response({:error, {:api_error, status, body}}) do
    {:error, "API error (#{status}): #{inspect(body)}"}
  end

  defp handle_api_response({:error, reason}) do
    {:error, "Request failed: #{inspect(reason)}"}
  end
end
