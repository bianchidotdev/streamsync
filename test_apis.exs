# Test script for Spotify and Tidal API functionality
# Usage: cd streamsync && mix run test_apis.exs

# Load aliases
alias Streamsync.{Accounts, Repo, Spotify, Tidal}
alias Streamsync.Music.Track

defmodule APITester do
  @moduledoc """
  Test script for API functionality with real tokens.
  """

  def run do
    IO.puts("🎵 Streamsync API Tester")
    IO.puts("=" |> String.duplicate(50))

    case get_test_user() do
      {:ok, user} ->
        IO.puts("✅ Found user: #{user.email}")
        run_tests(user)

      {:error, :no_users} ->
        IO.puts("❌ No users found in database. Please register a user first.")

      {:error, reason} ->
        IO.puts("❌ Error finding user: #{inspect(reason)}")
    end
  end

  defp get_test_user do
    case Repo.all(Accounts.User) do
      [] ->
        {:error, :no_users}

      [user | _] ->
        user_with_connections = Repo.preload(user, :provider_connections)
        {:ok, user_with_connections}
    end
  end

  defp run_tests(user) do
    check_connections(user)

    if has_spotify_connection?(user) do
      IO.puts("\n🎧 Testing Spotify API...")
      test_spotify_apis(user)
    else
      IO.puts("\n⚠️  No Spotify connection found")
    end

    if has_tidal_connection?(user) do
      IO.puts("\n🌊 Testing Tidal API...")
      test_tidal_apis(user)
    else
      IO.puts("\n⚠️  No Tidal connection found")
    end

    if has_spotify_connection?(user) and has_tidal_connection?(user) do
      IO.puts("\n🔄 Testing Cross-Platform Search...")
      test_cross_platform_search(user)
    end
  end

  defp check_connections(user) do
    IO.puts("\n📋 Provider Connections:")

    connections = user.provider_connections

    if Enum.empty?(connections) do
      IO.puts("❌ No provider connections found")
    end

    for connection <- connections do
      status = if connection.access_token, do: "✅", else: "❌"
      expires = format_expiry(connection.expires_at)
      IO.puts("#{status} #{connection.provider}: #{expires}")
    end
  end

  defp format_expiry(nil), do: "no expiry"

  defp format_expiry(datetime) do
    case DateTime.compare(datetime, DateTime.utc_now()) do
      :gt -> "expires #{DateTime.to_string(datetime)}"
      _ -> "⚠️  EXPIRED"
    end
  end

  defp has_spotify_connection?(user) do
    Enum.any?(user.provider_connections, &(&1.provider == "spotify"))
  end

  defp has_tidal_connection?(user) do
    Enum.any?(user.provider_connections, &(&1.provider == "tidal"))
  end

  # Spotify API Tests
  defp test_spotify_apis(user) do
    test_spotify_saved_tracks(user)
    test_spotify_playlists(user)
    test_spotify_search(user)
  end

  defp test_spotify_saved_tracks(user) do
    IO.puts("\n  📚 Testing spotify get_saved_tracks...")

    case Spotify.get_saved_tracks(user, limit: 5) do
      {:ok, %{items: tracks, total: total}} ->
        IO.puts("    ✅ Found #{length(tracks)} tracks (#{total} total)")

        if length(tracks) > 0 do
          track = List.first(tracks)
          IO.puts("    🎵 Sample: #{track.artist} - #{track.name}")
        end

      {:error, reason} ->
        IO.puts("    ❌ Error: #{inspect(reason)}")
    end
  end

  defp test_spotify_playlists(user) do
    IO.puts("\n  📁 Testing get_playlists...")

    case Spotify.get_playlists(user, limit: 5) do
      {:ok, %{items: playlists}} ->
        IO.puts("    ✅ Found #{length(playlists)} playlists")

        if length(playlists) > 0 do
          playlist = List.first(playlists)
          IO.puts("    🎵 Sample: #{playlist.name} (#{playlist.track_count} tracks)")

          # Test playlist tracks
          test_spotify_playlist_tracks(user, playlist.id, playlist.name)
        end

      {:error, reason} ->
        IO.puts("    ❌ Error: #{inspect(reason)}")
    end
  end

  defp test_spotify_playlist_tracks(user, playlist_id, playlist_name) do
    IO.puts("\n  🎵 Testing playlist tracks for '#{playlist_name}'...")

    case Spotify.get_playlist_tracks(user, playlist_id, limit: 3) do
      {:ok, %{items: tracks}} ->
        IO.puts("    ✅ Found #{length(tracks)} tracks in playlist")

        for track <- tracks do
          IO.puts("    • #{track.artist} - #{track.name}")
        end

      {:error, reason} ->
        IO.puts("    ❌ Error: #{inspect(reason)}")
    end
  end

  defp test_spotify_search(user) do
    IO.puts("\n  🔍 Testing search_tracks...")

    query = "Bohemian Rhapsody Queen"

    case Spotify.search_tracks(user, query, limit: 3) do
      {:ok, tracks} ->
        IO.puts("    ✅ Found #{length(tracks)} tracks for '#{query}'")

        for track <- tracks do
          IO.puts("    • #{track.artist} - #{track.name}")
        end

      {:error, reason} ->
        IO.puts("    ❌ Error: #{inspect(reason)}")
    end
  end

  # Tidal API Tests
  defp test_tidal_apis(user) do
    # TODO: re-enable when this works
    # test_tidal_saved_tracks(user)
    test_tidal_playlists(user)
    test_tidal_search(user)
  end

  defp test_tidal_saved_tracks(user) do
    IO.puts("\n  📚 Testing tidal get_saved_tracks...")

    case Tidal.get_saved_tracks(user) do
      {:ok, tracks} ->
        IO.puts("    ✅ Found #{length(tracks)} saved tracks")

        if length(tracks) > 0 do
          track = List.first(tracks)
          IO.puts("    🎵 Sample: #{Track.artists_string(track)} - #{track.name}")
        end

      {:error, reason} ->
        IO.puts("    ❌ Error: #{inspect(reason)}")
    end
  end

  defp test_tidal_playlists(user) do
    IO.puts("\n  📁 Testing tidal get_playlists...")

    case Tidal.get_playlists(user) do
      {:ok, playlists} ->
        IO.puts("    ✅ Found #{length(playlists)} playlists")

        if length(playlists) > 0 do
          playlist = List.first(playlists)
          IO.puts("    🎵 Sample: #{playlist.name} (#{playlist.track_count} tracks)")

          # Test playlist tracks
          test_tidal_playlist_tracks(user, playlist.id, playlist.name)
        end

      {:error, reason} ->
        IO.puts("    ❌ Error: #{inspect(reason)}")
    end
  end

  defp test_tidal_playlist_tracks(user, playlist_id, playlist_name) do
    IO.puts("\n  🎵 Testing playlist tracks for '#{playlist_name}'...")

    case Tidal.get_playlist_tracks(user, playlist_id) do
      {:ok, tracks} ->
        limited_tracks = Enum.take(tracks, 3)

        IO.puts(
          "    ✅ Found #{length(tracks)} tracks in playlist (showing #{length(limited_tracks)})"
        )

        for track <- limited_tracks do
          IO.puts("    • #{Track.artists_string(track)} - #{track.name}")
        end

      {:error, reason} ->
        IO.puts("    ❌ Error: #{inspect(reason)}")
    end
  end

  defp test_tidal_search(user) do
    IO.puts("\n  🔍 Testing search_tracks...")

    query = "Bohemian Rhapsody Queen"

    case Tidal.search_tracks(user, query, limit: 3) do
      {:ok, tracks} ->
        IO.puts("    ✅ Found #{length(tracks)} tracks for '#{query}'")

        for track <- tracks do
          IO.puts("    • #{Track.artists_string(track)} - #{track.name}")
        end

      {:error, reason} ->
        IO.puts("    ❌ Error: #{inspect(reason)}")
    end
  end

  # Cross-platform tests
  defp test_cross_platform_search(user) do
    IO.puts("\n🔄 Testing cross-platform search functionality...")

    # Get some Spotify tracks
    case Spotify.get_saved_tracks(user, limit: 3) do
      {:ok, %{items: spotify_tracks}} when spotify_tracks != [] ->
        IO.puts("  📥 Got #{length(spotify_tracks)} Spotify tracks to search on Tidal")

        # Convert Spotify track maps to Track structs
        tracks =
          spotify_tracks
          |> Enum.map(fn track_map ->
            Track.from_spotify(%{
              "id" => track_map.id,
              "name" => track_map.name,
              "artists" => [%{"name" => track_map.artist}],
              "album" => %{"name" => track_map.album},
              "duration_ms" => track_map.duration_ms,
              "external_urls" => %{"spotify" => track_map.external_url},
              "preview_url" => track_map.preview_url
            })
          end)

        # Search for them on Tidal
        case Tidal.search_tracks_on_tidal(user, tracks, "Test Playlist") do
          {:ok, %{found: found, not_found: not_found}} ->
            IO.puts("  ✅ Cross-platform search completed!")
            IO.puts("    📍 Found on Tidal: #{length(found)}")
            IO.puts("    ❌ Not found on Tidal: #{length(not_found)}")

            if length(found) > 0 do
              IO.puts("\n  🎯 Successful matches:")

              for {original, tidal_match} <- Enum.take(found, 2) do
                IO.puts("    • #{Track.artists_string(original)} - #{original.name}")
                IO.puts("      → #{Track.artists_string(tidal_match)} - #{tidal_match.name}")
              end
            end

            if length(not_found) > 0 do
              IO.puts("\n  ❌ Not found:")

              for track <- Enum.take(not_found, 2) do
                IO.puts("    • #{Track.format(track)}")
              end
            end

          {:error, reason} ->
            IO.puts("  ❌ Cross-platform search failed: #{inspect(reason)}")
        end

      {:ok, %{items: []}} ->
        IO.puts("  ⚠️  No saved Spotify tracks found to test with")

      {:error, reason} ->
        IO.puts("  ❌ Error getting Spotify tracks: #{inspect(reason)}")
    end
  end
end

# Helper module for interactive testing
defmodule Interactive do
  @moduledoc """
  Interactive functions for manual testing.
  """

  def help do
    IO.puts("""
    🎵 Interactive API Testing Commands:

    # Get a user (loads first user from DB with connections)
    user = Interactive.get_user()

    # Test individual APIs
    Interactive.test_spotify(user)
    Interactive.test_tidal(user)

    # Search for specific tracks
    Interactive.search_spotify(user, "song artist")
    Interactive.search_tidal(user, "song artist")

    # Cross-platform search
    Interactive.cross_search(user, [
      %{name: "Song", artist: "Artist", album: "Album"}
    ])

    # Create Track structs for testing
    track = Interactive.create_test_track()
    """)
  end

  def get_user do
    case Repo.all(Accounts.User) do
      [user | _] -> Repo.preload(user, :provider_connections)
      [] -> nil
    end
  end

  def test_spotify(user) do
    IO.puts("🎧 Testing Spotify APIs...")

    case Spotify.get_saved_tracks(user, limit: 3) do
      {:ok, %{items: tracks}} ->
        IO.puts("✅ Saved tracks: #{length(tracks)}")
        tracks

      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
        nil
    end
  end

  def test_tidal(user) do
    IO.puts("🌊 Testing Tidal APIs...")

    case Tidal.get_saved_tracks(user) do
      {:ok, tracks} ->
        limited = Enum.take(tracks, 3)
        IO.puts("✅ Saved tracks: #{length(tracks)} (showing #{length(limited)})")
        limited

      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
        nil
    end
  end

  def search_spotify(user, query) do
    case Spotify.search_tracks(user, query, limit: 5) do
      {:ok, tracks} ->
        IO.puts("🔍 Spotify search results for '#{query}': #{length(tracks)}")

        for track <- tracks do
          IO.puts("  • #{track.artist} - #{track.name}")
        end

        tracks

      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
        nil
    end
  end

  def search_tidal(user, query) do
    case Tidal.search_tracks(user, query, limit: 5) do
      {:ok, tracks} ->
        IO.puts("🔍 Tidal search results for '#{query}': #{length(tracks)}")

        for track <- tracks do
          IO.puts("  • #{Track.artists_string(track)} - #{track.name}")
        end

        tracks

      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
        nil
    end
  end

  def cross_search(user, track_data) when is_list(track_data) do
    tracks =
      Enum.map(track_data, fn data ->
        %Track{
          id: Map.get(data, :id, "test_#{:rand.uniform(1000)}"),
          name: Map.get(data, :name, "Unknown Track"),
          artists: [Map.get(data, :artist, "Unknown Artist")],
          album: Map.get(data, :album),
          duration_ms: Map.get(data, :duration_ms),
          external_url: nil,
          preview_url: nil,
          service: "test",
          service_metadata: nil
        }
      end)

    case Tidal.search_tracks_on_tidal(user, tracks, "Test Search") do
      {:ok, %{found: found, not_found: not_found}} ->
        IO.puts("🔄 Cross-platform search results:")
        IO.puts("  ✅ Found: #{length(found)}")
        IO.puts("  ❌ Not found: #{length(not_found)}")
        {found, not_found}

      {:error, reason} ->
        IO.puts("❌ Error: #{inspect(reason)}")
        nil
    end
  end

  def create_test_track do
    %Track{
      id: "test_#{:rand.uniform(10000)}",
      name: "Bohemian Rhapsody",
      artists: ["Queen"],
      album: "A Night at the Opera",
      duration_ms: 355_000,
      external_url: nil,
      preview_url: nil,
      service: "test",
      service_metadata: nil
    }
  end
end

# Main execution
case System.argv() do
  ["interactive"] ->
    IO.puts("🎵 Starting interactive mode...")
    IO.puts("Use Interactive.help() to see available commands")

  _ ->
    APITester.run()
end
