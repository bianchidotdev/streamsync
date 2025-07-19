defmodule StreamsyncWeb.SyncSongsLive.Index do
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveDashboard.ProcessesPage
  use StreamsyncWeb, :live_view

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
     |> assign(:songs, %AsyncResult{loading: true, ok?: true})
     |> assign(:selected_songs, [])
     |> assign(:loading, false)}
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

    {:noreply,
     socket
     |> assign(:from_provider, provider)
     |> assign_async(:songs, fn ->
       Process.sleep(500)
       {:ok, %{songs: fetch_songs_from_provider(provider, user)}}
     end)
     |> assign(:selected_songs, [])}
  end

  @impl true
  def handle_event("select_to_provider", %{"provider" => provider}, socket) do
    {:noreply,
     socket
     |> assign(:to_provider, provider)}
  end

  # @impl true
  # def handle_event("load_songs", _params, socket) do
  #   %{from_provider: provider, current_user: user} = socket.assigns

  #   # Start async operation to load songs
  #   {:noreply,
  #    socket
  #    |> assign_async(:songs_loader, fn ->
  #      # Add artificial delay to simulate network request
  #      Process.sleep(500)
  #      {:ok, %{songs: fetch_songs_from_provider(provider, user)}}
  #    end)}
  # end

  @impl true
  def handle_event("toggle_select", %{"id" => song_id}, socket) do
    selected_songs = socket.assigns.selected_songs

    updated_selected_songs =
      if song_id in selected_songs do
        List.delete(selected_songs, song_id)
      else
        [song_id | selected_songs]
      end

    {:noreply, assign(socket, :selected_songs, updated_selected_songs)}
  end

  @impl true
  def handle_event("toggle_select_all", _params, socket) do
    songs =
      case socket.assigns.songs.result do
        {:ok, %{songs: songs}} -> songs
        _ -> []
      end

    selected_songs = socket.assigns.selected_songs

    # If all songs are selected, unselect all. Otherwise, select all.
    updated_selected_songs =
      if length(selected_songs) == length(songs) do
        []
      else
        Enum.map(songs, & &1.id)
      end

    {:noreply, assign(socket, :selected_songs, updated_selected_songs)}
  end

  @impl true
  def handle_event("create_sync_job", _params, socket) do
    %{
      from_provider: from_provider,
      to_provider: to_provider,
      selected_songs: selected_songs,
      current_user: _current_user
    } = socket.assigns

    # Create a sync job - this would call your actual job creation module
    # job = Streamsync.Sync.create_job(_current_user, %{
    #   source: from_provider,
    #   destination: to_provider,
    #   songs: selected_songs
    # })

    # For now, just show a success message
    {:noreply,
     socket
     |> put_flash(
       :info,
       "Sync job created to sync #{length(selected_songs)} songs from #{from_provider} to #{to_provider}"
     )
     |> push_navigate(to: ~p"/sync")}
  end

  # Stub function to get available providers for the user
  # In a real implementation, this would check which providers the user has connected
  defp get_available_providers(_user) do
    ["spotify", "tidal", "apple_music"]
  end

  # Stub function to fetch songs from a specific provider
  # In a real implementation, this would use the appropriate API client
  defp fetch_songs_from_provider(provider, _user) do
    # This would be replaced with actual API calls
    # Simulating a delay for loading
    Process.sleep(500)

    # Return dummy data based on the provider
    songs =
      case provider do
        "spotify" ->
          [
            %{
              id: "s1",
              name: "Bohemian Rhapsody",
              artist: "Queen",
              album: "A Night at the Opera"
            },
            %{id: "s2", name: "Hotel California", artist: "Eagles", album: "Hotel California"},
            %{
              id: "s3",
              name: "Sweet Child O' Mine",
              artist: "Guns N' Roses",
              album: "Appetite for Destruction"
            },
            %{
              id: "s4",
              name: "Stairway to Heaven",
              artist: "Led Zeppelin",
              album: "Led Zeppelin IV"
            },
            %{id: "s5", name: "Imagine", artist: "John Lennon", album: "Imagine"}
          ]

        "tidal" ->
          [
            %{id: "t1", name: "Thriller", artist: "Michael Jackson", album: "Thriller"},
            %{
              id: "t2",
              name: "Like a Rolling Stone",
              artist: "Bob Dylan",
              album: "Highway 61 Revisited"
            },
            %{
              id: "t3",
              name: "I Want to Hold Your Hand",
              artist: "The Beatles",
              album: "Meet the Beatles!"
            },
            %{id: "t4", name: "Billie Jean", artist: "Michael Jackson", album: "Thriller"},
            %{id: "t5", name: "Smells Like Teen Spirit", artist: "Nirvana", album: "Nevermind"}
          ]

        "apple_music" ->
          [
            %{id: "a1", name: "Yesterday", artist: "The Beatles", album: "Help!"},
            %{id: "a2", name: "Good Vibrations", artist: "The Beach Boys", album: "Smiley Smile"},
            %{
              id: "a3",
              name: "Johnny B. Goode",
              artist: "Chuck Berry",
              album: "Chuck Berry Is on Top"
            },
            %{
              id: "a4",
              name: "Respect",
              artist: "Aretha Franklin",
              album: "I Never Loved a Man the Way I Love You"
            },
            %{id: "a5", name: "What's Going On", artist: "Marvin Gaye", album: "What's Going On"}
          ]

        _ ->
          []
      end

    songs
  end
end
