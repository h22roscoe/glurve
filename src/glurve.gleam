import game/game_socket
import gleam/erlang/process
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/option.{None, Some}
import lobby/lobby_manager
import mist
import router
import wisp
import wisp/wisp_mist

// MAIN ------------------------------------------------------------------------

pub fn main() {
  wisp.configure_logger()

  let lobby_manager_subject = process.new_subject()
  let _lobby_manager = lobby_manager.start(lobby_manager_subject)

  let secret_key_base = "glurve"

  let wisp_handler =
    router.handle_request(lobby_manager_subject)
    |> wisp_mist.handler(secret_key_base)

  let overall_handler = fn(req: request.Request(mist.Connection)) -> response.Response(
    mist.ResponseData,
  ) {
    case request.path_segments(req) {
      ["ws", game_id] -> serve_game(req, game_id, lobby_manager_subject)
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

fn serve_game(
  req: request.Request(mist.Connection),
  game_id: String,
  lobby_manager_subject: process.Subject(lobby_manager.LobbyManagerMsg),
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

  let assert Some(game_info) =
    lobby_manager.get_game(lobby_manager_subject, game_id)

  mist.websocket(
    request: req,
    on_init: game_socket.init_game_socket(_, user_id, game_info.topic),
    handler: game_socket.loop_game_socket,
    on_close: game_socket.close_game_socket,
  )
}
