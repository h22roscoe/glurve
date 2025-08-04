import game/game_socket
import gleam/bytes_tree
import gleam/erlang/application
import gleam/erlang/process
import gleam/function
import gleam/http.{Https}
import gleam/http/cookie
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import gleam/option.{None, Some}
import gluid
import lobby/lobby_manager
import lobby/lobby_socket
import lobby/lobby_socket
import lustre/attribute
import lustre/element
import lustre/element/html.{html}
import lustre/server_component
import mist.{type Connection, type ResponseData}

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let lobby_manager_subject = process.new_subject()

  let assert Ok(_) =
    fn(request: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(request) {
        [] -> serve_lobby_html(request)
        [game_id] -> serve_game_html(request, game_id)
        ["lustre", "runtime.mjs"] -> serve_runtime()
        ["ws"] -> serve_lobby(request, lobby_manager_subject)
        ["ws", game_id] -> serve_game(request, game_id, lobby_manager_subject)
        _ -> response.set_body(response.new(404), mist.Bytes(bytes_tree.new()))
      }
    }
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(1234)
    |> mist.start

  process.sleep_forever()
}

fn glurve_user_id() -> String {
  gluid.guidv4()
}

// HTML ------------------------------------------------------------------------

fn serve_game_html(
  request: Request(Connection),
  game_id: String,
) -> Response(ResponseData) {
  let possible_user_id =
    request.get_cookies(request)
    |> list.fold(None, fn(acc, c) {
      case c {
        #("glurve_user_id", id) -> Some(id)
        _ -> acc
      }
    })

  let add_cookie = case possible_user_id {
    None -> fn(res) -> Response(ResponseData) {
      response.set_cookie(
        res,
        "glurve_user_id",
        glurve_user_id(),
        cookie.defaults(Https),
      )
    }
    Some(_) -> function.identity
  }

  let html =
    html([attribute.lang("en")], [
      html.head([], [
        html.meta([attribute.charset("utf-8")]),
        html.meta([
          attribute.name("viewport"),
          attribute.content("width=device-width, initial-scale=1"),
        ]),
        html.title([], "Glurve Fever"),
        html.script(
          [attribute.type_("module"), attribute.src("/lustre/runtime.mjs")],
          "",
        ),
      ]),
      html.body([attribute.style("height", "100dvh")], [
        server_component.element(
          [server_component.route("/ws/" <> game_id)],
          [],
        ),
      ]),
    ])
    |> element.to_document_string_tree
    |> bytes_tree.from_string_tree

  response.new(200)
  |> response.set_body(mist.Bytes(html))
  |> response.set_header("content-type", "text/html")
  |> add_cookie
}

fn serve_lobby_html(request: Request(Connection)) -> Response(ResponseData) {
  todo
}

// JAVASCRIPT ------------------------------------------------------------------

fn serve_runtime() -> Response(ResponseData) {
  let assert Ok(lustre_priv) = application.priv_directory("lustre")
  let file_path = lustre_priv <> "/static/lustre-server-component.min.mjs"

  case mist.send_file(file_path, offset: 0, limit: None) {
    Ok(file) ->
      response.new(200)
      |> response.prepend_header("content-type", "application/javascript")
      |> response.set_body(file)

    Error(_) ->
      response.new(404)
      |> response.set_body(mist.Bytes(bytes_tree.new()))
  }
}

// WEBSOCKET -------------------------------------------------------------------

fn serve_game(
  request: Request(Connection),
  game_id: String,
  lobby_manager_subject: process.Subject(lobby_socket.LobbySocketMessage),
) -> Response(ResponseData) {
  let assert Some(game_info) =
    lobby_manager.get_game(lobby_manager_subject, game_id)

  let assert Some(user_id) =
    request.get_cookies(request)
    |> list.fold(None, fn(acc, c) {
      case c {
        #("glurve_user_id", id) -> Some(id)
        _ -> acc
      }
    })
    as "User ID cookie not found"

  mist.websocket(
    request:,
    on_init: game_socket.init_game_socket(_, user_id, game_info.topic),
    handler: game_socket.loop_game_socket,
    on_close: game_socket.close_game_socket,
  )
}

fn serve_lobby(
  request: Request(Connection),
  lobby_manager_subject: process.Subject(lobby_socket.LobbySocketMessage),
) -> Response(ResponseData) {
  mist.websocket(
    request:,
    on_init: lobby_socket.init_lobby_socket(_, lobby_manager_subject),
    handler: lobby_socket.loop_lobby_socket,
    on_close: lobby_socket.close_lobby_socket,
  )
}
