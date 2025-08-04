import gleam/erlang/application
import gleam/erlang/process
import gleam/http
import gleam/json
import gleam/string_tree
import gluid
import lobby/lobby_manager
import lustre/attribute
import lustre/element
import lustre/element/html.{html}
import lustre/server_component
import wisp.{type Request, type Response}

pub fn handle_request(
  lobby_manager_subject: process.Subject(lobby_manager.LobbyManagerMsg),
) -> fn(Request) -> Response {
  fn(request) {
    use req <- middleware(request)

    case wisp.path_segments(req) {
      [] -> serve_lobby_html(req)
      ["game", game_id] -> serve_game_html(req, game_id)
      ["create-game", game_name] ->
        handle_create_game(req, game_name, lobby_manager_subject)
      ["join-game", game_id] ->
        handle_join_game(req, game_id, lobby_manager_subject)
      ["leave-game"] -> handle_leave_game(req, lobby_manager_subject)
      ["list-games"] -> handle_list_games(req, lobby_manager_subject)
      ["get-player-game"] -> handle_get_player_game(req, lobby_manager_subject)
      ["player-disconnected", player_id] ->
        handle_player_disconnected(req, player_id, lobby_manager_subject)
      ["lustre", "runtime.mjs"] -> serve_runtime(req)
      _ -> wisp.not_found()
    }
  }
}

fn middleware(req: Request, handle_request: fn(Request) -> Response) -> Response {
  // Permit browsers to simulate methods other than GET and POST using the
  // `_method` query parameter.
  let req = wisp.method_override(req)

  // Log information about the request and response.
  use <- wisp.log_request(req)

  // Return a default 500 response if the request handler crashes.
  use <- wisp.rescue_crashes

  // Rewrite HEAD requests to GET requests and return an empty body.
  use req <- wisp.handle_head(req)

  // Known-header based CSRF protection for non-HEAD/GET requests
  // use req <- wisp.csrf_known_header_protection(req)

  // Handle the request!
  handle_request(req)
}

fn glurve_user_id() -> String {
  gluid.guidv4()
}

// HANDLERS --------------------------------------------------------------------

fn handle_create_game(
  req: Request,
  game_name: String,
  lobby_manager_subject: process.Subject(lobby_manager.LobbyManagerMsg),
) -> Response {
  case wisp.get_cookie(req, "glurve_user_id", wisp.Signed) {
    Ok(user_id) -> {
      let created =
        lobby_manager.create_game(lobby_manager_subject, user_id, game_name)
      case created {
        Ok(game_info) -> {
          let res =
            lobby_manager.game_info_to_json(game_info)
            |> json.to_string
            |> string_tree.from_string

          wisp.json_response(res, 200)
        }
        Error(_error) -> wisp.bad_request()
      }
    }
    Error(_) -> wisp.bad_request()
  }
}

fn handle_join_game(
  request: Request,
  game_id: String,
  lobby_manager_subject: process.Subject(lobby_manager.LobbyManagerMsg),
) -> Response {
  todo
}

fn handle_leave_game(
  request: Request,
  lobby_manager_subject: process.Subject(lobby_manager.LobbyManagerMsg),
) -> Response {
  todo
}

fn handle_list_games(
  request: Request,
  lobby_manager_subject: process.Subject(lobby_manager.LobbyManagerMsg),
) -> Response {
  todo
}

fn handle_get_player_game(
  request: Request,
  lobby_manager_subject: process.Subject(lobby_manager.LobbyManagerMsg),
) -> Response {
  todo
}

fn handle_player_disconnected(
  request: Request,
  player_id: String,
  lobby_manager_subject: process.Subject(lobby_manager.LobbyManagerMsg),
) -> Response {
  todo
}

// HTML ------------------------------------------------------------------------

fn serve_game_html(_req: Request, game_id: String) -> Response {
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

  wisp.html_response(html, 200)
}

fn serve_lobby_html(req: Request) -> Response {
  let html =
    html([attribute.lang("en")], [
      html.head([], [
        html.meta([attribute.charset("utf-8")]),
        html.meta([
          attribute.name("viewport"),
          attribute.content("width=device-width, initial-scale=1"),
        ]),
        html.title([], "Glurve Fever"),
      ]),
    ])
    |> element.to_document_string_tree

  wisp.html_response(html, 200)
  |> wisp.set_cookie(
    req,
    "glurve_user_id",
    glurve_user_id(),
    wisp.PlainText,
    // 30 days
    60 * 60 * 24 * 30,
  )
}

// JAVASCRIPT ------------------------------------------------------------------

fn serve_runtime(req: Request) -> Response {
  use <- wisp.require_method(req, http.Get)

  let assert Ok(file_path) = application.priv_directory("lustre")
  let file_path = file_path <> "/static/lustre-server-component.min.mjs"

  wisp.ok()
  |> wisp.set_header("content-type", "application/javascript")
  |> wisp.file_download(named: file_path, from: file_path)
}
