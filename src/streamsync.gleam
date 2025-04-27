import gleam/io
import httpbin
import tidal

pub fn main() -> Nil {
  io.println("Hello from streamsync!")
  httpbin.send_form()
  echo tidal.get_oauth_token()
  Nil
}
