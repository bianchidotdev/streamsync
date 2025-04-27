import envoy
import gleam/uri

const local_callback_url = "localhost:4200/callback"

const scopes = ["playlist-modify-public", "playlist-modify-private"]

pub fn spotify_auth() {
  let client_id = envoy.get("SPOTIFY_CLIENT_ID")
  let client_secret = envoy.get("SPOTIFY_CLIENT_SECRET")
  let current_user = envoy.get("SPOTIFY_CURRENT_USER")
}

pub fn callback_url() {
  uri.parse(local_callback_url)
}
