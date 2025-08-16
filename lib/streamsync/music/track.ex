defmodule Streamsync.Music.Track do
  @moduledoc """
  Generic track representation that can be used across different music services.

  ## Example Usage

      # Create a track from Spotify data
      track = Track.from_spotify(%{
        "id" => "4iV5W9uYEdYUVa79Axb7Rh",
        "name" => "Bohemian Rhapsody",
        "artists" => [%{"name" => "Queen"}],
        "album" => %{"name" => "A Night at the Opera"},
        "duration_ms" => 355000
      })

      # Create a track from Tidal data
      track = Track.from_tidal(%{
        "id" => 12345,
        "title" => "Bohemian Rhapsody",
        "artist" => %{"name" => "Queen"},
        "album" => %{"title" => "A Night at the Opera"},
        "duration" => 355
      })

      # Access track information
      IO.puts(Track.artists_string(track))  # "Queen"
      IO.puts(Track.format(track))          # "12345: Queen - Bohemian Rhapsody"

      # Use in Tidal search
      {:ok, results} = Streamsync.Tidal.search_tracks_on_tidal(user, [track])
  """

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          artists: [String.t()],
          album: String.t() | nil,
          duration_ms: integer() | nil,
          external_url: String.t() | nil,
          preview_url: String.t() | nil,
          service: String.t(),
          service_metadata: map() | nil
        }

  @enforce_keys [:id, :name, :artists, :service]
  defstruct [
    :id,
    :name,
    :artists,
    :album,
    :duration_ms,
    :external_url,
    :preview_url,
    :service,
    :service_metadata
  ]

  @doc """
  Creates a new Track struct from a map of attributes.
  """
  def new(attrs) do
    %__MODULE__{
      id: Map.get(attrs, :id) || Map.get(attrs, "id"),
      name: Map.get(attrs, :name) || Map.get(attrs, "name") || Map.get(attrs, "title"),
      artists: normalize_artists(Map.get(attrs, :artists) || Map.get(attrs, "artists")),
      album: Map.get(attrs, :album) || Map.get(attrs, "album"),
      duration_ms: Map.get(attrs, :duration_ms) || Map.get(attrs, "duration_ms"),
      external_url: Map.get(attrs, :external_url) || Map.get(attrs, "external_url"),
      preview_url: Map.get(attrs, :preview_url) || Map.get(attrs, "preview_url"),
      service: Map.get(attrs, :service) || Map.get(attrs, "service"),
      service_metadata: Map.get(attrs, :service_metadata) || Map.get(attrs, "service_metadata")
    }
  end

  @doc """
  Creates a Track from Spotify track data.
  """
  def from_spotify(spotify_data) do
    artists = extract_spotify_artists(spotify_data)
    duration_ms = Map.get(spotify_data, "duration_ms")

    %__MODULE__{
      id: Map.get(spotify_data, "id"),
      name: Map.get(spotify_data, "name"),
      artists: artists,
      album: extract_spotify_album(spotify_data),
      duration_ms: duration_ms,
      external_url: get_in(spotify_data, ["external_urls", "spotify"]),
      preview_url: Map.get(spotify_data, "preview_url"),
      service: "spotify",
      service_metadata: spotify_data
    }
  end

  @doc """
  Creates a Track from Tidal track data.
  """
  def from_tidal(tidal_data) do
    attrs = Map.get(tidal_data, "attributes", %{})

    %__MODULE__{
      id: Map.get(tidal_data, "id"),
      name: Map.get(attrs, "title") || Map.get(tidal_data, "name") || "Unknown name",
      artists: extract_tidal_artists(tidal_data),
      album: extract_tidal_album(tidal_data),
      duration_ms: (Map.get(tidal_data, "duration") || 0) * 1000,
      external_url: Map.get(tidal_data, "url"),
      preview_url: Map.get(tidal_data, "previewUrl"),
      service: "tidal",
      service_metadata: tidal_data
    }
  end

  @doc """
  Returns the primary artist name.
  """
  def primary_artist(%__MODULE__{artists: []}), do: "Unknown Artist"
  def primary_artist(%__MODULE__{artists: [first | _]}), do: first

  @doc """
  Returns all artists as a comma-separated string.
  """
  def artists_string(%__MODULE__{artists: artists}) do
    case artists do
      [] -> "Unknown Artist"
      artists -> Enum.join(artists, ", ")
    end
  end

  @doc """
  Formats the track for display.
  """
  def format(%__MODULE__{} = track) do
    "#{track.id}: #{artists_string(track)} - #{track.name}"
  end

  @doc """
  Returns the duration in seconds.
  """
  def duration_seconds(%__MODULE__{duration_ms: nil}), do: nil
  def duration_seconds(%__MODULE__{duration_ms: duration_ms}), do: div(duration_ms, 1000)

  # Private helper functions

  defp normalize_artists(nil), do: []
  defp normalize_artists([]), do: []

  defp normalize_artists(artists) when is_list(artists) do
    artists
    |> Enum.map(fn
      artist when is_binary(artist) -> artist
      %{"name" => name} -> name
      artist when is_map(artist) -> Map.get(artist, "name", "Unknown")
      _ -> "Unknown"
    end)
    |> Enum.reject(&(&1 == "" or &1 == "Unknown"))
  end

  defp normalize_artists(artist) when is_binary(artist), do: [artist]
  defp normalize_artists(_), do: []

  defp extract_spotify_artists(spotify_data) do
    case Map.get(spotify_data, "artists") do
      artists when is_list(artists) ->
        artists
        |> Enum.map(&Map.get(&1, "name"))
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp extract_spotify_album(spotify_data) do
    case Map.get(spotify_data, "album") do
      %{"name" => name} -> name
      _ -> nil
    end
  end

  defp extract_tidal_artists(tidal_data) do
    cond do
      Map.has_key?(tidal_data, "artists") and is_list(tidal_data["artists"]) ->
        tidal_data["artists"]
        |> Enum.map(&Map.get(&1, "name"))
        |> Enum.reject(&is_nil/1)

      Map.has_key?(tidal_data, "artist") ->
        case tidal_data["artist"] do
          %{"name" => name} -> [name]
          name when is_binary(name) -> [name]
          _ -> []
        end

      true ->
        []
    end
  end

  defp extract_tidal_album(tidal_data) do
    case Map.get(tidal_data, "album") do
      %{"title" => title} -> title
      %{"name" => name} -> name
      title when is_binary(title) -> title
      _ -> nil
    end
  end
end
