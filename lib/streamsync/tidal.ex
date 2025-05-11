defmodule Streamsync.Tidal do
  @auth_base_api_url "https://auth.tidal.com"
  @auth_token_path "/v1/oauth2/token"
  @api_base_api_url "https://openapi.tidal.com"

  def client() do
    {:ok, token} = get_oauth_token()

    Req.new(
      base_url: @api_base_api_url,
      headers: [
        {"Authorization", "Bearer #{token.access_token}"},
        {"Accept", "application/vnd.tidal.v1+json"}
      ]
    )
  end

  def get_album(client, album_id) do
    client
    |> Req.get(url: "/v2/albums/#{album_id}?countryCode=US")

    # |> handle_response()
  end

  # client credentials flow that will definitely not continue to work for this
  # project
  def auth_client() do
    Req.new(base_url: @auth_base_api_url)
  end

  def get_oauth_token() do
    form = [grant_type: "client_credentials"]
    client_id = System.get_env("TIDAL_CLIENT_ID")
    client_secret = System.get_env("TIDAL_CLIENT_SECRET")

    resp =
      auth_client()
      |> Req.post(
        url: @auth_token_path,
        form: form,
        auth: {:basic, "#{client_id}:#{client_secret}"}
      )

    case resp do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, Streamsync.Tidal.Token.parse_token_response(body)}

      {:error, reason} ->
        {:error, "Request failed: #{inspect(reason)}"}
    end
  end
end

defmodule Streamsync.Tidal.Token do
  defstruct access_token: nil, expires_at: nil, token_type: nil, scope: nil

  def parse_token_response(body) do
    expires_at =
      case body["expires_in"] do
        nil -> nil
        expires_in -> DateTime.utc_now() |> DateTime.add(expires_in)
      end

    %Streamsync.Tidal.Token{
      access_token: body["access_token"],
      expires_at: expires_at,
      token_type: body["token_type"],
      scope: body["scope"]
    }
  end
end
