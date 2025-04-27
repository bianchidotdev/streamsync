import envoy
import gleam/bit_array
import gleam/fetch
import gleam/fetch/form_data
import gleam/http
import gleam/http/request
import gleam/javascript/promise

pub fn get_oauth_token() {
  let assert Ok(client_id) = envoy.get("TIDAL_CLIENT_ID")
  let assert Ok(client_secret) = envoy.get("TIDAL_CLIENT_SECRET")
  // let assert Ok(redirect_url) = envoy.get("TIDAL_REDIRECT_URI")
  // let assert Ok(redirect_uri) = uri.parse(redirect_url)

  let assert Ok(token_req) =
    request.to("https://auth.tidal.com/v1/oauth2/token")

  let creds =
    bit_array.from_string(client_id <> ":" <> client_secret)
    |> bit_array.base64_encode(True)

  let payload_form =
    form_data.new()
    |> form_data.set("grant_type", "client_credentials")

  let token_req =
    token_req
    |> request.set_method(http.Post)
    // |> request.set_header("Content-Type", "multipart/form-data")
    |> request.set_header("Content-Type", "application/x-www-form-urlencoded")
    |> request.set_header("Authorization", "Basic " <> creds)
    |> request.set_body(payload_form)

  echo token_req

  use resp <- promise.try_await(fetch.send_form_data(token_req))
  use body <- promise.try_await(fetch.read_json_body(resp))

  echo resp
  echo body
  promise.resolve(Ok(Nil))
  // Handle the response
  // case response {
  //   Ok(token) -> {
  //     io.println("Access Token: " <> token)
  //   }
  //   Err(error) -> {
  //     io.println("Error: " <> error)
  //   }
  // }
}
