defmodule Streamsync.Music.PlaylistTest do
  use ExUnit.Case, async: true

  alias Streamsync.Music.{Playlist, Track}

  describe "new/1" do
    test "creates a playlist with required fields" do
      attrs = %{
        id: "test_id",
        name: "Test Playlist",
        tracks: [],
        service: "spotify"
      }

      playlist = Playlist.new(attrs)

      assert playlist.id == "test_id"
      assert playlist.name == "Test Playlist"
      assert playlist.tracks == []
      assert playlist.service == "spotify"
      assert playlist.track_count == 0
    end

    test "uses track count from tracks list when not provided" do
      tracks = [
        %Track{id: "1", name: "Song 1", artists: ["Artist 1"], service: "spotify"},
        %Track{id: "2", name: "Song 2", artists: ["Artist 2"], service: "spotify"}
      ]

      attrs = %{
        id: "test_id",
        name: "Test Playlist",
        tracks: tracks,
        service: "spotify"
      }

      playlist = Playlist.new(attrs)

      assert playlist.track_count == 2
      assert length(playlist.tracks) == 2
    end

    test "handles string keys" do
      attrs = %{
        "id" => "test_id",
        "name" => "Test Playlist",
        "tracks" => [],
        "service" => "spotify"
      }

      playlist = Playlist.new(attrs)

      assert playlist.id == "test_id"
      assert playlist.name == "Test Playlist"
    end

    test "provides default values for optional fields" do
      attrs = %{
        id: "test_id",
        tracks: [],
        service: "spotify"
      }

      playlist = Playlist.new(attrs)

      assert playlist.name == "Unknown Playlist"
      assert playlist.description == nil
      assert playlist.created_at == nil
    end
  end

  describe "from_spotify/2" do
    test "creates playlist from Spotify data" do
      spotify_data = %{
        "id" => "37i9dQZF1DXcBWIGoYBM5M",
        "name" => "Today's Top Hits",
        "description" => "The most played songs right now",
        "tracks" => %{"total" => 50},
        "external_urls" => %{
          "spotify" => "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"
        },
        "images" => [%{"url" => "https://example.com/image.jpg"}]
      }

      tracks = [
        %Track{id: "1", name: "Song 1", artists: ["Artist 1"], service: "spotify"}
      ]

      playlist = Playlist.from_spotify(spotify_data, tracks)

      assert playlist.id == "37i9dQZF1DXcBWIGoYBM5M"
      assert playlist.name == "Today's Top Hits"
      assert playlist.description == "The most played songs right now"
      assert playlist.tracks == tracks
      assert playlist.track_count == 50
      assert playlist.external_url == "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"
      assert playlist.image_url == "https://example.com/image.jpg"
      assert playlist.service == "spotify"
    end

    test "handles missing optional fields" do
      spotify_data = %{
        "id" => "test_id",
        "name" => "Test Playlist"
      }

      playlist = Playlist.from_spotify(spotify_data, [])

      assert playlist.id == "test_id"
      assert playlist.name == "Test Playlist"
      assert playlist.description == nil
      assert playlist.external_url == nil
      assert playlist.image_url == nil
      assert playlist.track_count == 0
    end

    test "uses tracks length when total not provided" do
      spotify_data = %{
        "id" => "test_id",
        "name" => "Test Playlist"
      }

      tracks = [
        %Track{id: "1", name: "Song 1", artists: ["Artist 1"], service: "spotify"},
        %Track{id: "2", name: "Song 2", artists: ["Artist 2"], service: "spotify"}
      ]

      playlist = Playlist.from_spotify(spotify_data, tracks)

      assert playlist.track_count == 2
    end
  end

  describe "from_tidal/2" do
    test "creates playlist from Tidal data" do
      tidal_data = %{
        "id" => "12345",
        "attributes" => %{
          "name" => "My Tidal Playlist",
          "description" => "A great playlist",
          "numberOfItems" => 25,
          "dateCreated" => "2023-01-01T00:00:00Z"
        },
        "relationships" => %{
          "coverArt" => %{
            "links" => %{
              "self" => "https://example.com/cover.jpg"
            }
          }
        }
      }

      tracks = [
        %Track{id: "1", name: "Song 1", artists: ["Artist 1"], service: "tidal"}
      ]

      playlist = Playlist.from_tidal(tidal_data, tracks)

      assert playlist.id == "12345"
      assert playlist.name == "My Tidal Playlist"
      assert playlist.description == "A great playlist"
      assert playlist.tracks == tracks
      assert playlist.track_count == 25
      assert playlist.external_url == "https://tidal.com/browse/playlist/12345"
      assert playlist.image_url == "https://example.com/cover.jpg"
      assert playlist.service == "tidal"
      assert playlist.created_at != nil
    end

    test "handles missing attributes" do
      tidal_data = %{
        "id" => "test_id"
      }

      playlist = Playlist.from_tidal(tidal_data, [])

      assert playlist.id == "test_id"
      assert playlist.name == "Unknown Playlist"
      assert playlist.description == nil
      assert playlist.track_count == 0
    end
  end

  describe "track_count/1" do
    test "returns the number of tracks in the playlist" do
      tracks = [
        %Track{id: "1", name: "Song 1", artists: ["Artist 1"], service: "spotify"},
        %Track{id: "2", name: "Song 2", artists: ["Artist 2"], service: "spotify"}
      ]

      playlist = %Playlist{
        id: "test_id",
        name: "Test Playlist",
        tracks: tracks,
        service: "spotify"
      }

      assert Playlist.track_count(playlist) == 2
    end
  end

  describe "empty?/1" do
    test "returns true for empty playlist" do
      playlist = %Playlist{
        id: "test_id",
        name: "Test Playlist",
        tracks: [],
        service: "spotify"
      }

      assert Playlist.empty?(playlist) == true
    end

    test "returns false for non-empty playlist" do
      tracks = [
        %Track{id: "1", name: "Song 1", artists: ["Artist 1"], service: "spotify"}
      ]

      playlist = %Playlist{
        id: "test_id",
        name: "Test Playlist",
        tracks: tracks,
        service: "spotify"
      }

      assert Playlist.empty?(playlist) == false
    end
  end

  describe "format/1" do
    test "formats playlist for display" do
      tracks = [
        %Track{id: "1", name: "Song 1", artists: ["Artist 1"], service: "spotify"},
        %Track{id: "2", name: "Song 2", artists: ["Artist 2"], service: "spotify"}
      ]

      playlist = %Playlist{
        id: "test_id",
        name: "My Playlist",
        tracks: tracks,
        service: "spotify"
      }

      assert Playlist.format(playlist) == "My Playlist (2 tracks)"
    end
  end
end
