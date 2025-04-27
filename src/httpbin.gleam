import gleam/bit_array
import gleam/fetch
import gleam/fetch/form_data
import gleam/http
import gleam/http/request
import gleam/javascript/promise
import gleam/result

pub fn send_form() {
  let id = "test"
  let secret = "testsecret"
  // let assert Ok(token_req) = request.to("https://httpbin.org/post")
  // let token_url = "https://auth.tidal.com/v1/oauth2/token"
  let token_url = "https://httpbin.org/post"

  let creds =
    bit_array.from_string(id <> ":" <> secret)
    |> bit_array.base64_encode(False)

  let payload_form =
    form_data.new()
    |> form_data.set("grant_type", "client_credentials")

  echo form_data.get(payload_form, "grant_type")

  use res <- promise.try_await(
    token_url
    |> request.to
    |> promise.resolve
    |> promise.await(fn(req_promise) {
      case req_promise {
        Ok(req) -> {
          req
          |> request.set_body(payload_form)
          |> request.set_method(http.Post)
          |> request.set_header(
            "Content-Type",
            "application/x-www-form-urlencoded",
          )
          |> request.set_header("Authorization", "Basic " <> creds)
          |> fetch.send_form_data
          |> promise.try_await(fetch.read_json_body)
          |> promise.map(fn(res_promise) {
            res_promise
            |> result.replace_error("Could not get access token")
          })
        }
        Error(_) -> {
          promise.resolve(Error("Failed to create request"))
        }
      }
    }),
  )

  echo res

  echo res.body
  promise.resolve(Ok(Nil))
  // let token_req =
  //   token_req
  //   |> request.set_method(http.Post)
  //   |> request.set_header("Authorization", "Basic " <> creds)

  // echo token_req

  // let token_req =
  //   token_req
  //   |> request.set_body(payload_form)

  // echo token_req

  // use resp <- promise.try_await(fetch.send_form_data(token_req))

  // use body <- promise.try_await(fetch.read_text_body(resp))

  // echo resp
  // echo body
  // promise.resolve(Ok(Nil))
}
