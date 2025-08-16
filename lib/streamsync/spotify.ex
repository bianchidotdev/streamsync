defmodule Streamsync.Spotify do
  @moduledoc """
  Spotify API client that uses OAuth tokens from user provider connections.
  """

  alias Streamsync.Accounts.UserProviderConnection
  alias Streamsync.Repo
  import Ecto.Query

  @base_url "https://api.spotify.com/v1"

  @type pagination_opts :: [
          limit: pos_integer(),
          offset: non_neg_integer(),
          all_pages: boolean()
        ]

  @type paginated_response :: %{
          items: list(),
          next: String.t() | nil,
          previous: String.t() | nil,
          total: non_neg_integer(),
          limit: pos_integer(),
          offset: non_neg_integer()
        }

  @doc """
  Fetches the user's saved tracks from Spotify.

  ## Options

  * `:limit` - Number of tracks to return per page (1-50, default: 20)
  * `:offset` - The index of the first track to return (default: 0)
  * `:all_pages` - Whether to fetch all pages automatically (default: false)

  ## Examples

      # Get first page with default limit
      {:ok, response} = get_saved_tracks(user)

      # Get specific page
      {:ok, response} = get_saved_tracks(user, limit: 10, offset: 20)

      # Get all tracks across all pages
      {:ok, all_tracks} = get_saved_tracks(user, all_pages: true)
  """
  def get_saved_tracks(user, opts \\ []) do
    paginated_request(user, "/me/tracks", &parse_tracks/1, opts)
  end

  @doc """
  Fetches the user's playlists from Spotify.

  ## Options

  * `:limit` - Number of playlists to return per page (1-50, default: 20)
  * `:offset` - The index of the first playlist to return (default: 0)
  * `:all_pages` - Whether to fetch all pages automatically (default: false)
  """
  def get_playlists(user, opts \\ []) do
    paginated_request(user, "/me/playlists", &parse_playlists/1, opts)
  end

  @doc """
  Searches for tracks on Spotify.
  """
  def search_tracks(user, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)

    case get_user_connection(user, "spotify") do
      {:ok, connection} ->
        with {:ok, token} <- ensure_valid_token(connection),
             {:ok, response} <-
               make_request("/search", token, %{
                 q: query,
                 type: "track",
                 limit: limit
               }) do
          {:ok, parse_search_tracks(response)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a specific playlist by ID.
  """
  def get_playlist(user, playlist_id) do
    case get_user_connection(user, "spotify") do
      {:ok, connection} ->
        with {:ok, token} <- ensure_valid_token(connection),
             {:ok, response} <- make_request("/playlists/#{playlist_id}", token) do
          {:ok, response}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets tracks from a specific playlist.

  ## Options

  * `:limit` - Number of tracks to return per page (1-50, default: 20)
  * `:offset` - The index of the first track to return (default: 0)
  * `:all_pages` - Whether to fetch all pages automatically (default: false)
  """
  def get_playlist_tracks(user, playlist_id, opts \\ []) do
    path = "/playlists/#{playlist_id}/tracks"
    paginated_request(user, path, &parse_playlist_tracks/1, opts)
  end

  @doc """
  Creates a new playlist for the user.
  """
  def create_playlist(user, name, description \\ nil) do
    case get_user_connection(user, "spotify") do
      {:ok, connection} ->
        with {:ok, token} <- ensure_valid_token(connection),
             {:ok, response} <-
               make_post_request("/users/#{connection.provider_uid}", token, %{
                 name: name,
                 description: description,
                 public: false
               }) do
          {:ok, response}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Adds tracks to a playlist.
  """
  def add_tracks_to_playlist(user, playlist_id, track_uris) do
    case get_user_connection(user, "spotify") do
      {:ok, connection} ->
        with {:ok, token} <- ensure_valid_token(connection),
             #  {"uris": ["spotify:track:4iV5W9uYEdYUVa79Axb7Rh","spotify:track:1301WleyT98MSxVHPZCA6M", "spotify:episode:512ojhOuo1ktJprKbVcKyQ"]}
             #  limit of 100 / request
             {:ok, response} <-
               make_post_request("/playlists/#{playlist_id}/tracks", token, %{
                 uris: track_uris
               }) do
          {:ok, response}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generic paginated request handler that can fetch single pages or all pages.

  Returns either a paginated response (when all_pages: false) or just the items (when all_pages: true).
  """
  def paginated_request(user, path, parser_fn, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    offset = Keyword.get(opts, :offset, 0)
    all_pages = Keyword.get(opts, :all_pages, false)

    case get_user_connection(user, "spotify") do
      {:ok, connection} ->
        with {:ok, token} <- ensure_valid_token(connection) do
          if all_pages do
            fetch_all_pages(path, token, parser_fn, limit)
          else
            fetch_single_page(path, token, parser_fn, %{limit: limit, offset: offset})
          end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

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
    client_id = Application.get_env(:ueberauth, Ueberauth.Strategy.Spotify.OAuth)[:client_id]

    client_secret =
      Application.get_env(:ueberauth, Ueberauth.Strategy.Spotify.OAuth)[:client_secret]

    auth_header = Base.encode64("#{client_id}:#{client_secret}")

    headers = [
      {"Authorization", "Basic #{auth_header}"},
      {"Content-Type", "application/x-www-form-urlencoded"}
    ]

    body =
      URI.encode_query(%{
        grant_type: "refresh_token",
        refresh_token: refresh_token
      })

    case Req.post("https://accounts.spotify.com/api/token", headers: headers, body: body) do
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

  defp make_request(path, token, params \\ %{}) do
    url = @base_url <> path

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    case Req.get(url, headers: headers, params: params) do
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

  defp make_post_request(path, token, body) do
    url = @base_url <> path

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
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

  defp get_retry_after(headers) do
    case Enum.find(headers, fn {key, _} -> String.downcase(key) == "retry-after" end) do
      {_, value} -> String.to_integer(value)
      nil -> 60
    end
  end

  defp parse_tracks(%{"items" => items}) do
    Enum.map(items, fn item ->
      track = if Map.has_key?(item, "track"), do: item["track"], else: item

      %{
        id: track["id"],
        name: track["name"],
        artist: get_primary_artist(track["artists"]),
        album: track["album"]["name"],
        duration_ms: track["duration_ms"],
        external_url: track["external_urls"]["spotify"],
        preview_url: track["preview_url"]
      }
    end)
  end

  defp parse_playlists(%{"items" => items}) do
    Enum.map(items, fn playlist ->
      %{
        id: playlist["id"],
        name: playlist["name"],
        description: playlist["description"],
        track_count: playlist["tracks"]["total"],
        external_url: playlist["external_urls"]["spotify"],
        image_url: get_playlist_image(playlist["images"])
      }
    end)
  end

  defp parse_search_tracks(%{"tracks" => %{"items" => items}}) do
    parse_tracks(%{"items" => items})
  end

  defp parse_playlist_tracks(%{"items" => items}) do
    parse_tracks(%{"items" => items})
  end

  defp get_primary_artist(artists) when is_list(artists) do
    case List.first(artists) do
      nil -> "Unknown Artist"
      artist -> artist["name"]
    end
  end

  defp get_primary_artist(_), do: "Unknown Artist"

  defp get_playlist_image(images) when is_list(images) do
    case List.first(images) do
      nil -> nil
      image -> image["url"]
    end
  end

  defp get_playlist_image(_), do: nil

  defp fetch_single_page(path, token, parser_fn, params) do
    case make_request(path, token, params) do
      {:ok, response} ->
        parsed_items = parser_fn.(response)

        paginated_response = %{
          items: parsed_items,
          next: response["next"],
          previous: response["previous"],
          total: response["total"],
          limit: response["limit"],
          offset: response["offset"]
        }

        {:ok, paginated_response}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_all_pages(path, token, parser_fn, limit, acc \\ []) do
    offset = length(acc)
    params = %{limit: limit, offset: offset}

    case make_request(path, token, params) do
      {:ok, response} ->
        items = parser_fn.(response)
        all_items = acc ++ items

        if response["next"] do
          fetch_all_pages(path, token, parser_fn, limit, all_items)
        else
          {:ok, all_items}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
