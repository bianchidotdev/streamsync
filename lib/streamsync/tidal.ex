defmodule Streamsync.Tidal do
  @moduledoc """
  Tidal API client that uses OAuth tokens from user provider connections.
  """

  require Logger
  alias Streamsync.Accounts.UserProviderConnection
  alias Streamsync.Music.Track
  alias Streamsync.Repo
  import Ecto.Query

  # @base_url "https://api.tidal.com/v1"
  @base_url "https://openapi.tidal.com/v2"
  @auth_url "https://auth.tidal.com/v1/oauth2"

  @doc """
  Fetches the user's favorite tracks from Tidal.

  TODO: THIS IS BROKEN 🚧 - Tidal does not seem to support saved songs with their official API
  """
  def get_saved_tracks(user) do
    case get_user_auth(user) do
      {:ok, {connection, token}} ->
        case make_request("/userCollections/#{connection.provider_uid}", token, %{
               limit: 50
             }) do
          {:ok, response} -> {:ok, parse_tracks(response)}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def fetch_tracks_by_ids(user, track_ids) do
    case get_user_auth(user) do
      {:ok, {_connection, token}} ->
        # TODO: implement limit and pagination
        # params = Enum.map(track_ids, fn id -> {:filter, id} end)

        case make_request("/tracks", token, %{filter: track_ids}) do
          {:ok, response} -> {:ok, parse_tracks(response)}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches the user's playlists from Tidal.
  """
  def get_playlists(user) do
    case get_user_auth(user) do
      {:ok, {connection, token}} ->
        case make_request("/userCollections/#{connection.provider_uid}", token, %{
               include: "playlists",
               limit: 50
             }) do
          {:ok, response} -> {:ok, parse_playlists(response)}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Searches for tracks on Tidal.
  """
  def search_tracks(user, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    case get_user_auth(user) do
      {:ok, {_connection, token}} ->
        case make_request("/search/tracks", token, %{
               query: query,
               limit: limit,
               countryCode: "US"
             }) do
          {:ok, response} -> {:ok, parse_search_tracks(response)}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a specific playlist by ID.
  """
  def get_playlist(user, playlist_id) do
    case get_user_auth(user) do
      {:ok, {_connection, token}} ->
        case make_request("/playlists/#{playlist_id}", token) do
          {:ok, response} -> {:ok, response}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a new playlist for the user.
  """
  def create_playlist(user, name, description \\ nil) do
    case get_user_auth(user) do
      {:ok, {connection, token}} ->
        body = %{
          data: %{
            type: "playlists",
            attributes: %{
              name: name,
              description: description || "",
              accessType: "PRIVATE"
            }
          }
        }

        case make_post_request(
               "/playlists",
               token,
               body
             ) do
          {:ok, response} -> {:ok, response}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Adds tracks to a playlist.
  """
  def add_tracks_to_playlist(user, playlist_id, track_ids) do
    case get_user_auth(user) do
      {:ok, {_connection, token}} ->
        body = %{
          data:
            Enum.map(track_ids, fn track_id ->
              %{
                type: "tracks",
                id: track_id
              }
            end)
        }

        case make_post_request("/playlists/#{playlist_id}/relationships/items", token, body) do
          {:ok, response} -> {:ok, response}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_playlist_tracks(user, playlist_id) do
    case get_user_auth(user) do
      {:ok, {_connection, token}} ->
        with {:ok, playlist_data} <-
               make_request("/playlists/#{playlist_id}", token, %{limit: 50, include: :items}),
             {:ok, track_ids} <- parse_track_ids_from_playlist(playlist_data),
             {:ok, tracks} <- fetch_tracks_by_ids(user, track_ids) do
          {:ok, tracks}
        else
          {:error, reason} ->
            {:error, reason}
        end

      # case make_request("/playlists/#{playlist_id}", token, %{
      #        include: :items,
      #        limit: 50
      #      }) do
      #   {:ok, response} ->
      #     {:ok, parse_playlist_tracks(response)}

      #   {:error, reason} ->
      #     {:error, reason}
      # end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Searches for tracks on Tidal and returns matches and not found tracks.

  Takes a list of Track structs and searches for them on Tidal.
  Returns a map with :found and :not_found lists.
  """
  def search_tracks_on_tidal(user, tracks, playlist_name \\ "Unknown") do
    case get_user_auth(user) do
      {:ok, {_connection, _token}} ->
        IO.puts("Searching Tidal for #{length(tracks)} tracks in playlist '#{playlist_name}'")

        {found, not_found} =
          Enum.reduce(tracks, {[], []}, fn track, {found_acc, not_found_acc} ->
            case search_track_on_tidal(user, track) do
              {:ok, tidal_track} ->
                {[{track, tidal_track} | found_acc], not_found_acc}

              {:error, :not_found} ->
                track_desc = Track.format(track)
                IO.puts("\u001b[91mCould not find the track #{track_desc}\u001b[0m")
                {found_acc, [track | not_found_acc]}

              {:error, _reason} ->
                track_desc = Track.format(track)
                IO.puts("\u001b[91mError searching for track #{track_desc}\u001b[0m")
                {found_acc, [track | not_found_acc]}
            end
          end)

        # Write not found songs to file
        if length(not_found) > 0 do
          write_not_found_tracks(not_found)
        end

        {:ok, %{found: Enum.reverse(found), not_found: Enum.reverse(not_found)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  defp search_track_on_tidal(user, track) do
    # Create search query from track
    artists = Track.artists_string(track)
    track_name = track.name

    query = "#{artists} #{track_name}"

    case search_tracks(user, query, limit: 10) do
      {:ok, tidal_tracks} ->
        # Convert tidal track maps to Track structs
        tidal_track_structs = Enum.map(tidal_tracks, &track_map_to_struct/1)

        case find_best_match(track, tidal_track_structs) do
          nil -> {:error, :not_found}
          match -> {:ok, match}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp track_map_to_struct(%Track{} = track), do: track

  defp track_map_to_struct(track_map) do
    %Track{
      id: to_string(track_map.id),
      name: track_map.name,
      artists: [track_map.artist],
      album: track_map.album,
      duration_ms: track_map.duration_ms,
      external_url: track_map.external_url,
      preview_url: track_map.preview_url,
      service: "tidal",
      service_metadata: nil
    }
  end

  defp find_best_match(source_track, tidal_tracks) do
    source_name = String.downcase(source_track.name)
    source_artists = String.downcase(Track.artists_string(source_track))

    Enum.find(tidal_tracks, fn tidal_track ->
      tidal_name = String.downcase(tidal_track.name)
      tidal_artist = String.downcase(Track.artists_string(tidal_track))

      # Simple matching - could be enhanced with fuzzy matching
      String.contains?(tidal_name, source_name) or
        (String.jaro_distance(tidal_name, source_name) > 0.8 and
           String.jaro_distance(tidal_artist, source_artists) > 0.6)
    end)
  end

  defp write_not_found_tracks(tracks) do
    file_name = "songs_not_found.txt"

    content =
      tracks
      |> Enum.map(&Track.format/1)
      |> Enum.join("\n")

    case File.write(file_name, content <> "\n", [:append, :utf8]) do
      :ok ->
        IO.puts("Written #{length(tracks)} not found tracks to #{file_name}")

      {:error, reason} ->
        IO.puts("Failed to write to #{file_name}: #{reason}")
    end
  end

  defp get_user_auth(user) do
    case get_user_connection(user, "tidal") do
      {:ok, connection} ->
        case ensure_valid_token(connection) do
          {:ok, token} -> {:ok, {connection, token}}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_user_connection(user, provider) do
    connection =
      from(c in UserProviderConnection,
        where: c.user_id == ^user.id and c.provider == ^provider
      )
      |> Repo.one()

    case connection do
      nil -> {:error, :no_connection}
      connection -> {:ok, connection}
    end
  end

  defp ensure_valid_token(connection) do
    if token_expired?(connection) do
      refresh_token(connection)
    else
      {:ok, connection.access_token}
    end
  end

  defp token_expired?(connection) do
    case connection.expires_at do
      nil -> false
      expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :gt
    end
  end

  defp refresh_token(connection) do
    case connection.refresh_token do
      nil ->
        {:error, :no_refresh_token}

      refresh_token ->
        with {:ok, tokens} <- request_token_refresh(refresh_token),
             {:ok, updated_connection} <- update_connection_tokens(connection, tokens) do
          {:ok, updated_connection.access_token}
        end
    end
  end

  defp request_token_refresh(refresh_token) do
    headers = [
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    {_, tidal_ops} =
      Application.get_env(:ueberauth, Ueberauth)
      |> get_in([:providers, :tidal])

    tidal_scopes = tidal_ops[:default_scope]

    body =
      URI.encode_query(%{
        client_id: Application.get_env(:ueberauth, Ueberauth.Strategy.Tidal.OAuth)[:client_id],
        grant_type: "refresh_token",
        refresh_token: refresh_token,
        scope: tidal_scopes
      })

    case Req.post("#{@auth_url}/token", headers: headers, body: body) do
      {:ok, %{status: 200, body: response}} ->
        expires_at =
          DateTime.add(DateTime.utc_now(), response["expires_in"], :second)
          |> DateTime.truncate(:second)

        tokens = %{
          access_token: response["access_token"],
          refresh_token: response["refresh_token"] || refresh_token,
          expires_at: expires_at
        }

        {:ok, tokens}

      {:ok, %{status: status, body: body}} ->
        {:error, {:token_refresh_failed, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp update_connection_tokens(connection, tokens) do
    connection
    |> Ecto.Changeset.change(tokens)
    |> Repo.update()
  end

  defp make_post_request(path, token, body) do
    url = "#{@base_url}#{path}"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/vnd.api+json"}
    ]

    case Req.post(url, headers: headers, json: body) do
      {:ok, %{status: status, body: response_body}} when status in [200, 201] ->
        {:ok, response_body}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 429, headers: headers}} ->
        retry_after = get_retry_after(headers)
        {:error, {:rate_limited, retry_after}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp make_request(path, token, params \\ %{}) do
    url = @base_url <> path

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"},
      {"X-Tidal-Token", token}
    ]

    params = Map.put_new(params, :countryCode, "US")

    kw_params =
      Enum.map(params, fn
        {k, v} when is_list(v) -> Enum.map(v, fn item -> {k, item} end)
        {k, v} -> {k, v}
      end)

    case Req.get(url, headers: headers, params: kw_params) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %{status: 401}} ->
        {:error, :unauthorized}

      {:ok, %{status: 429, headers: headers}} ->
        retry_after = get_retry_after(headers)
        {:error, {:rate_limited, retry_after}}

      {:ok, %{status: status, body: body}} ->
        {:error, {:api_error, status, body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp get_retry_after(headers) do
    case Enum.find(headers, fn {key, _} -> String.downcase(key) == "retry-after" end) do
      {_, value} -> String.to_integer(value)
      nil -> 60
    end
  end

  defp parse_tracks(%{"data" => data}) when is_list(data) do
    Enum.map(data, &parse_track/1)
  end

  defp parse_tracks(items) when is_list(items) do
    Enum.map(items, &parse_track/1)
  end

  defp parse_tracks(data) do
    Logger.error("Unexpected format")
    []
  end

  defp parse_track(%{"item" => track}) when is_map(track) do
    parse_track(track)
  end

  defp parse_track(track) when is_map(track) do
    Track.from_tidal(track)
  end

  defp parse_playlists(%{"included" => items}) when is_list(items) do
    Enum.map(items, &parse_playlist/1)
  end

  defp parse_playlists(%{"data" => data}) when is_list(data) do
    Enum.map(data, &parse_playlist/1)
  end

  defp parse_playlists(data) when is_map(data) do
    Logger.error("Unexpected data structure", Map.keys(data))
    []
  end

  defp parse_playlists(_) do
    Logger.error("Unexpected data structure")
    []
  end

  defp parse_playlist(playlist) when is_map(playlist) do
    attrs = Map.get(playlist, "attributes", %{})

    %{
      id: playlist["id"],
      name: attrs["name"] || "Unknown Playlist",
      description: attrs["description"],
      track_count: attrs["numberOfItems"] || 0,
      # TODO: get from attrs.externalLinks
      external_url: build_tidal_playlist_url(playlist["id"]),
      image_url:
        get_playlist_image(get_in(playlist, ["relationships", "coverArt", "links", "self"]))
    }
  end

  defp parse_track_ids_from_playlist(%{"data" => data, "included" => items})
       when is_list(items) do
    num_tracks = get_in(data, ["attributes", "numberOfItems"])

    case num_tracks do
      nil ->
        {:error, "Failed to parse playlist data"}

      num ->
        track_ids =
          Enum.map(items, fn item -> Map.get(item, "id") end)
          |> Enum.reject(&is_nil/1)

        if length(items) > length(track_ids) do
          Logger.warn("Could not find track IDs from playlist")
        end

        {:ok, track_ids}
    end
  end

  defp parse_track_ids_from_playlist(data) do
    Logger.error("Unexpected format")
    {:error, :unexpected_format}
  end

  defp parse_search_tracks(%{"tracks" => %{"items" => items}}) do
    parse_tracks(%{"items" => items})
  end

  defp parse_search_tracks(%{"tracks" => %{"data" => data}}) do
    parse_tracks(%{"data" => data})
  end

  defp parse_search_tracks(_), do: []

  # defp parse_playlist_tracks(%{"items" => items}) do
  #   parse_tracks(%{"items" => items})
  # end

  defp parse_playlist_tracks(%{"included" => items}) do
    parse_tracks(items)
  end

  defp parse_playlist_tracks(data) do
    Logger.error("Unexpected format")
    []
  end

  defp get_playlist_image(image) when is_binary(image) do
    # Tidal image URLs might need transformation
    if String.starts_with?(image, "http") do
      image
    else
      "https://resources.tidal.com/images/#{String.replace(image, "-", "/")}/1280x1280.jpg"
    end
  end

  defp get_playlist_image(_), do: nil

  defp build_tidal_url(track_id) when is_binary(track_id) do
    "https://tidal.com/browse/track/#{track_id}"
  end

  defp build_tidal_url(track_id) when is_integer(track_id) do
    "https://tidal.com/browse/track/#{track_id}"
  end

  defp build_tidal_url(_), do: nil

  defp build_tidal_playlist_url(playlist_uuid) when is_binary(playlist_uuid) do
    "https://listen.tidal.com/playlist/#{playlist_uuid}"
  end

  defp build_tidal_playlist_url(_), do: nil
end
