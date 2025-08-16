defmodule Streamsync.Sync.SyncJob do
  @moduledoc """
  Oban worker for processing music sync jobs between platforms.
  """

  use Oban.Worker, queue: :sync, max_attempts: 3

  alias Streamsync.Spotify
  alias Streamsync.Tidal
  alias Streamsync.Sync
  alias Streamsync.Music.{Track, Playlist}

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "user_id" => user_id,
          "from_provider" => from_provider,
          "to_provider" => to_provider,
          "sync_type" => sync_type,
          "source_provider_ids" => source_provider_ids,
          "sync_job_id" => sync_job_id
        }
      }) do
    user = Streamsync.Accounts.get_user!(user_id)

    # Update job status to processing
    Sync.update_sync_job_status(sync_job_id, :processing)

    # Broadcast job status update
    Phoenix.PubSub.broadcast(
      Streamsync.PubSub,
      "sync_jobs:#{user_id}",
      {:sync_job_updated, sync_job_id, :processing}
    )

    case sync(user, from_provider, to_provider, sync_type, source_provider_ids) do
      {:ok, results} ->
        # Update job status to completed
        Sync.update_sync_job_status(sync_job_id, :completed, %{
          synced_count: length(results[:synced]),
          failed_count: length(results[:failed]),
          results: results
        })

        # Broadcast completion
        Phoenix.PubSub.broadcast(
          Streamsync.PubSub,
          "sync_jobs:#{user_id}",
          {:sync_job_updated, sync_job_id, :completed}
        )

        :ok

      {:error, reason} ->
        # Update job status to failed
        Sync.update_sync_job_status(sync_job_id, :failed, %{error: reason})

        # Broadcast failure
        Phoenix.PubSub.broadcast(
          Streamsync.PubSub,
          "sync_jobs:#{user_id}",
          {:sync_job_updated, sync_job_id, :failed}
        )

        {:error, reason}
    end
  end

  # Private functions for syncing songs between platforms
  defp sync(user, from_provider, to_provider, "playlists", [source_playlist_id]) do
    with {:ok, source_playlist} <- fetch_playlist(user, from_provider, source_playlist_id),
         {:ok, target_playlist_id} <- create_playlist(user, to_provider, source_playlist.name),
         {:ok, results} <-
           sync_to_playlist(user, to_provider, target_playlist_id, source_playlist.tracks) do
      {:ok, results}
    end
  end

  defp sync(user, from_provider, to_provider, sync_type, source_provider_ids) do
    case sync_type do
      "playlists" ->
        with {:ok, source_playists} <-
               fetch_songs_from_provider(user, from_provider, source_provider_ids),
             {:ok, results} <- sync_to_destination(user, to_provider, source_playists) do
          {:ok, results}
        end

        # _ ->
        #   with {:ok, source_songs} <- fetch_songs_from_provider(user, from_provider, song_ids),
        #        {:ok, results} <- sync_to_destination(user, to_provider, source_songs) do
        #     {:ok, results}
        #   end
    end
  end

  defp fetch_playlist(user, "spotify", playlist_id) do
    with {:ok, playlist_data} <- Spotify.get_playlist(user, playlist_id),
         {:ok, tracks_data} <- Spotify.get_playlist_tracks(user, playlist_id, all_pages: true) do
      tracks = Enum.map(tracks_data, &Track.from_spotify/1)
      playlist = Playlist.from_spotify(playlist_data, tracks)
      {:ok, playlist}
    else
      {:error, reason} ->
        {:error, "Failed to fetch playlist from Spotify: #{inspect(reason)}"}
    end
  end

  defp fetch_playlist(user, "tidal", playlist_id) do
    with {:ok, playlist_data} <- Tidal.get_playlist(user, playlist_id),
         {:ok, tracks_data} <- Tidal.get_playlist_tracks(user, playlist_id) do
      tracks = Enum.map(tracks_data, &Track.from_tidal/1)
      playlist = Playlist.from_tidal(playlist_data, tracks)
      {:ok, playlist}
    else
      {:error, reason} ->
        {:error, "Failed to fetch playlist from Tidal: #{inspect(reason)}"}
    end
  end

  defp fetch_playlist(_user, provider, _playlist_id) do
    {:error, "Unsupported provider for playlist fetch: #{provider}"}
  end

  defp fetch_songs_from_provider(user, "spotify", song_ids) do
    # For now, we'll get all saved tracks and filter by IDs
    # In a real implementation, you'd want to fetch specific tracks by ID
    case Spotify.get_saved_tracks(user) do
      {:ok, tracks} ->
        filtered_tracks = Enum.filter(tracks, fn track -> track.id in song_ids end)
        {:ok, filtered_tracks}

      {:error, reason} ->
        {:error, "Failed to fetch from Spotify: #{inspect(reason)}"}
    end
  end

  defp fetch_songs_from_provider(user, "tidal", song_ids) do
    case Tidal.get_saved_tracks(user) do
      {:ok, tracks} ->
        filtered_tracks = Enum.filter(tracks, fn track -> track.id in song_ids end)
        {:ok, filtered_tracks}

      {:error, reason} ->
        {:error, "Failed to fetch from Tidal: #{inspect(reason)}"}
    end
  end

  defp fetch_songs_from_provider(_user, provider, _song_ids) do
    {:error, "Unsupported source provider: #{provider}"}
  end

  defp create_playlist(user, "spotify", playlist_name) do
    case Spotify.create_playlist(user, playlist_name) do
      {:ok, playlist} -> {:ok, playlist["id"]}
      {:error, reason} -> {:error, "Failed to create Spotify playlist: #{inspect(reason)}"}
    end
  end

  defp create_playlist(user, "tidal", playlist_name) do
    case Tidal.create_playlist(user, playlist_name) do
      {:ok, playlist} -> {:ok, playlist["id"]}
      {:error, reason} -> {:error, "Failed to create Tidal playlist: #{inspect(reason)}"}
    end
  end

  defp create_playlist(_user, provider, _playlist_name) do
    {:error, "Unsupported provider for playlist creation: #{provider}"}
  end

  defp sync_to_playlist(user, "spotify", playlist_id, tracks) do
    track_uris =
      Enum.map(tracks, fn track ->
        "spotify:track:#{track.id}"
      end)

    case Spotify.add_tracks_to_playlist(user, playlist_id, track_uris) do
      {:ok, _} ->
        {:ok, %{synced: tracks, failed: []}}

      {:error, reason} ->
        {:error, "Failed to add tracks to Spotify playlist: #{inspect(reason)}"}
    end
  end

  defp sync_to_playlist(user, "tidal", playlist_id, tracks) do
    track_ids = Enum.map(tracks, & &1.id)

    case Tidal.add_tracks_to_playlist(user, playlist_id, track_ids) do
      {:ok, _} ->
        {:ok, %{synced: tracks, failed: []}}

      {:error, reason} ->
        {:error, "Failed to add tracks to Tidal playlist: #{inspect(reason)}"}
    end
  end

  defp sync_to_playlist(_user, provider, _playlist_id, _tracks) do
    {:error, "Unsupported provider for playlist sync: #{provider}"}
  end

  defp sync_to_destination(user, "spotify", songs) do
    # For now, we'll simulate the sync process
    # In a real implementation, you'd use Spotify's API to add tracks to user's library
    simulate_sync_process(user, "spotify", songs)
  end

  defp sync_to_destination(user, "tidal", songs) do
    # For now, we'll simulate the sync process
    # In a real implementation, you'd use Tidal's API to add tracks to user's library
    simulate_sync_process(user, "tidal", songs)
  end

  defp sync_to_destination(_user, provider, _songs) do
    {:error, "Unsupported destination provider: #{provider}"}
  end

  # Simulate the sync process for demonstration
  defp simulate_sync_process(_user, _provider, songs) do
    # Simulate some processing time
    Process.sleep(1000)

    # Simulate some successes and failures
    {synced, failed} =
      Enum.split_with(songs, fn _song ->
        # 80% success rate for simulation
        :rand.uniform(100) <= 80
      end)

    {:ok, %{synced: synced, failed: failed}}
  end
end
