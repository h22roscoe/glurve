import app/app_shared_message.{type AppSharedMsg}
import app/app_socket
import gleam/erlang/process.{type Subject}
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor.{type Started}
import glubsub.{type Topic}
import lobby/lobby_manager.{type LobbyManagerMsg}
import mist
import router
import wisp
import wisp/wisp_mist

// MAIN ------------------------------------------------------------------------

pub fn main() {
  wisp.configure_logger()

  let assert Ok(topic) = glubsub.new_topic()
  let lobby_manager = lobby_manager.start(topic)

  let secret_key_base = "glurve"

  let wisp_handler =
    router.handle_request
    |> wisp_mist.handler(secret_key_base)

  let overall_handler = fn(req: request.Request(mist.Connection)) -> response.Response(
    mist.ResponseData,
  ) {
    case request.path_segments(req) {
      ["ws"] -> serve_app(req, topic, lobby_manager)
      _ -> wisp_handler(req)
    }
  }

  let assert Ok(_) =
    overall_handler
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(1234)
    |> mist.start

  process.sleep_forever()
}

// WEBSOCKET -------------------------------------------------------------------

fn serve_app(
  req: request.Request(mist.Connection),
  topic: Topic(AppSharedMsg),
  lobby_manager: Started(Subject(LobbyManagerMsg)),
) -> response.Response(mist.ResponseData) {
  let assert Some(user_id) =
    request.get_cookies(req)
    |> list.fold(None, fn(acc, c) {
      case c {
        #("glurve_user_id", id) -> Some(id)
        _ -> acc
      }
    })
    as "User ID cookie not found"

  mist.websocket(
    request: req,
    on_init: app_socket.init(_, user_id, topic, lobby_manager),
    handler: app_socket.loop_socket,
    on_close: app_socket.close_socket,
  )
}
