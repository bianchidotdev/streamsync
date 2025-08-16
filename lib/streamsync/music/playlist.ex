defmodule Streamsync.Music.Playlist do
  @moduledoc """
  Generic playlist representation that can be used across different music services.

  ## Example Usage

      # Create a playlist from Spotify data
      playlist = Playlist.from_spotify(%{
        "id" => "37i9dQZF1DXcBWIGoYBM5M",
        "name" => "Today's Top Hits",
        "description" => "The most played songs right now",
        "tracks" => %{"total" => 50},
        "external_urls" => %{"spotify" => "https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M"}
      }, tracks)

      # Create a playlist from Tidal data
      playlist = Playlist.from_tidal(%{
        "id" => "12345",
        "attributes" => %{
          "name" => "Today's Top Hits",
          "description" => "The most played songs right now",
          "numberOfItems" => 50
        }
      }, tracks)

      # Access playlist information
      IO.puts(playlist.name)          # "Today's Top Hits"
      IO.puts(length(playlist.tracks)) # 50
  """

  alias Streamsync.Music.Track

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t() | nil,
          tracks: [Track.t()],
          track_count: integer(),
          created_at: DateTime.t() | nil,
          external_url: String.t() | nil,
          image_url: String.t() | nil,
          service: String.t(),
          service_metadata: map() | nil
        }

  @enforce_keys [:id, :name, :tracks, :service]
  defstruct [
    :id,
    :name,
    :description,
    :tracks,
    :track_count,
    :created_at,
    :external_url,
    :image_url,
    :service,
    :service_metadata
  ]

  @doc """
  Creates a new Playlist struct from a map of attributes.
  """
  def new(attrs) do
    tracks = Map.get(attrs, :tracks) || Map.get(attrs, "tracks") || []

    %__MODULE__{
      id: Map.get(attrs, :id) || Map.get(attrs, "id"),
      name: Map.get(attrs, :name) || Map.get(attrs, "name") || "Unknown Playlist",
      description: Map.get(attrs, :description) || Map.get(attrs, "description"),
      tracks: tracks,
      track_count:
        Map.get(attrs, :track_count) || Map.get(attrs, "track_count") || length(tracks),
      created_at: parse_datetime(Map.get(attrs, :created_at) || Map.get(attrs, "created_at")),
      external_url: Map.get(attrs, :external_url) || Map.get(attrs, "external_url"),
      image_url: Map.get(attrs, :image_url) || Map.get(attrs, "image_url"),
      service: Map.get(attrs, :service) || Map.get(attrs, "service"),
      service_metadata: Map.get(attrs, :service_metadata) || Map.get(attrs, "service_metadata")
    }
  end

  @doc """
  Creates a Playlist from Spotify playlist data and tracks.
  """
  def from_spotify(spotify_data, tracks \\ []) do
    created_at = parse_spotify_date(spotify_data["added_at"])
    track_count = get_in(spotify_data, ["tracks", "total"]) || length(tracks)

    %__MODULE__{
      id: Map.get(spotify_data, "id"),
      name: Map.get(spotify_data, "name") || "Unknown Playlist",
      description: Map.get(spotify_data, "description"),
      tracks: tracks,
      track_count: track_count,
      created_at: created_at,
      external_url: get_in(spotify_data, ["external_urls", "spotify"]),
      image_url: extract_spotify_image(spotify_data["images"]),
      service: "spotify",
      service_metadata: spotify_data
    }
  end

  @doc """
  Creates a Playlist from Tidal playlist data and tracks.
  """
  def from_tidal(tidal_data, tracks \\ []) do
    attrs = Map.get(tidal_data, "attributes", %{})
    created_at = parse_tidal_date(attrs["dateCreated"])
    track_count = Map.get(attrs, "numberOfItems") || length(tracks)

    %__MODULE__{
      id: Map.get(tidal_data, "id"),
      name: Map.get(attrs, "name") || "Unknown Playlist",
      description: Map.get(attrs, "description"),
      tracks: tracks,
      track_count: track_count,
      created_at: created_at,
      external_url: build_tidal_playlist_url(tidal_data["id"]),
      image_url: extract_tidal_image(tidal_data),
      service: "tidal",
      service_metadata: tidal_data
    }
  end

  @doc """
  Returns the number of tracks in the playlist.
  """
  def track_count(%__MODULE__{tracks: tracks}) do
    length(tracks)
  end

  @doc """
  Returns whether the playlist is empty.
  """
  def empty?(%__MODULE__{tracks: []}), do: true
  def empty?(%__MODULE__{}), do: false

  @doc """
  Formats the playlist for display.
  """
  def format(%__MODULE__{} = playlist) do
    "#{playlist.name} (#{track_count(playlist)} tracks)"
  end

  # Private helper functions

  defp parse_datetime(nil), do: nil

  defp parse_datetime(datetime) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, dt, _} -> dt
      {:error, _} -> nil
    end
  end

  defp parse_datetime(%DateTime{} = datetime), do: datetime
  defp parse_datetime(_), do: nil

  defp parse_spotify_date(nil), do: nil

  defp parse_spotify_date(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, dt, _} -> dt
      {:error, _} -> nil
    end
  end

  defp parse_spotify_date(_), do: nil

  defp parse_tidal_date(nil), do: nil

  defp parse_tidal_date(date_string) when is_binary(date_string) do
    case DateTime.from_iso8601(date_string) do
      {:ok, dt, _} -> dt
      {:error, _} -> nil
    end
  end

  defp parse_tidal_date(_), do: nil

  defp extract_spotify_image(images) when is_list(images) do
    case List.first(images) do
      nil -> nil
      image -> image["url"]
    end
  end

  defp extract_spotify_image(_), do: nil

  defp extract_tidal_image(tidal_data) do
    case get_in(tidal_data, ["relationships", "coverArt", "links", "self"]) do
      url when is_binary(url) -> url
      _ -> nil
    end
  end

  defp build_tidal_playlist_url(playlist_id) when is_binary(playlist_id) do
    "https://tidal.com/browse/playlist/#{playlist_id}"
  end

  defp build_tidal_playlist_url(_), do: nil
end
