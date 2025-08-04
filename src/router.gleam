import gleam/erlang/application
import gleam/erlang/process
import gleam/http
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/string_tree
import gluid
import lobby/lobby_actor
import lustre/attribute
import lustre/element
import lustre/element/html.{html}
import lustre/server_component
import wisp.{type Request, type Response}

pub fn handle_request(
  lobby: actor.Started(process.Subject(lobby_actor.Message)),
) -> fn(Request) -> Response {
  fn(request) {
    use req <- middleware(request)

    // Serve static files from the public directory.
    let assert Ok(priv_dir) = application.priv_directory("glurve")
    use <- wisp.serve_static(req, under: "/static", from: priv_dir <> "/static")

    case wisp.path_segments(req) {
      [] -> serve_lobby_html(req)
      ["game", game_id] -> serve_game_html(req, game_id)
      ["create-game", game_name] -> handle_create_game(req, game_name, lobby)
      ["join-game", game_id] -> handle_join_game(req, game_id, lobby)
      ["leave-game"] -> handle_leave_game(req, lobby)
      ["list-games"] -> handle_list_games(req, lobby)
      ["get-player-game"] -> handle_get_player_game(req, lobby)
      ["player-disconnected", player_id] ->
        handle_player_disconnected(req, player_id, lobby)
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
  lobby: actor.Started(process.Subject(lobby_actor.Message)),
) -> Response {
  case wisp.get_cookie(req, "glurve_user_id", wisp.PlainText) {
    Ok(user_id) -> {
      let created = lobby_actor.create_game(lobby.data, user_id, game_name)
      case created {
        Ok(game_info) -> {
          let res =
            lobby_actor.game_info_to_json(game_info)
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
  lobby: actor.Started(process.Subject(lobby_actor.Message)),
) -> Response {
  case wisp.get_cookie(request, "glurve_user_id", wisp.PlainText) {
    Ok(user_id) -> {
      let joined = lobby_actor.join_game(lobby.data, user_id, game_id)
      case joined {
        Ok(game_info) -> {
          let res =
            lobby_actor.game_info_to_json(game_info)
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

fn handle_leave_game(
  request: Request,
  lobby: actor.Started(process.Subject(lobby_actor.Message)),
) -> Response {
  case wisp.get_cookie(request, "glurve_user_id", wisp.PlainText) {
    Ok(user_id) -> {
      let left = lobby_actor.leave_game(lobby.data, user_id)
      case left {
        Ok(_) -> wisp.json_response(string_tree.from_string("{}"), 200)
        Error(_error) -> wisp.bad_request()
      }
    }
    Error(_) -> wisp.bad_request()
  }
}

fn handle_list_games(
  _request: Request,
  lobby: actor.Started(process.Subject(lobby_actor.Message)),
) -> Response {
  let games = lobby_actor.list_games(lobby.data)
  let games_json =
    games
    |> list.map(lobby_actor.game_info_to_json)
    |> json.array(fn(x) { x })
    |> json.to_string
    |> string_tree.from_string

  wisp.json_response(games_json, 200)
}

fn handle_get_player_game(
  request: Request,
  lobby: actor.Started(process.Subject(lobby_actor.Message)),
) -> Response {
  case wisp.get_cookie(request, "glurve_user_id", wisp.PlainText) {
    Ok(user_id) -> {
      let player_game = lobby_actor.get_player_game(lobby.data, user_id)
      case player_game {
        Some(game_info) -> {
          let res =
            lobby_actor.game_info_to_json(game_info)
            |> json.to_string
            |> string_tree.from_string

          wisp.json_response(res, 200)
        }
        None -> wisp.json_response(string_tree.from_string("null"), 200)
      }
    }
    Error(_) -> wisp.bad_request()
  }
}

fn handle_player_disconnected(
  _request: Request,
  player_id: String,
  lobby: actor.Started(process.Subject(lobby_actor.Message)),
) -> Response {
  process.send(lobby.data, lobby_actor.PlayerDisconnected(player_id))
  wisp.json_response(string_tree.from_string("{}"), 200)
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
        html.script(
          [],
          "
        const glurve = document.querySelector('lustre-server-component');

        glurve.addEventListener('navigate', (event) => {
          console.log('navigate', event);
          window.location.href = event.detail;
        });
        ",
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
        html.title([], "Glurve Fever - Lobby"),
        html.link([
          attribute.rel("stylesheet"),
          attribute.href("/static/lobby.css"),
        ]),
      ]),
      html.body([], [
        html.div([attribute.class("container")], [
          html.div([attribute.class("header")], [
            html.h1([], [html.text("🎮 Glurve Fever Lobby")]),
            html.p([], [html.text("Create or join a multiplayer game")]),
          ]),
          html.div([attribute.class("content")], [
            html.div([attribute.class("section")], [
              html.h2([], [html.text("Create New Game")]),
              html.form([attribute.id("create-form")], [
                html.div([attribute.class("form-group")], [
                  html.label([attribute.for("game-name")], [
                    html.text("Game Name"),
                  ]),
                  html.input([
                    attribute.type_("text"),
                    attribute.id("game-name"),
                    attribute.placeholder("Enter game name"),
                    attribute.required(True),
                  ]),
                ]),
                html.button(
                  [attribute.type_("submit"), attribute.class("btn")],
                  [html.text("Create Game")],
                ),
              ]),
              html.div(
                [
                  attribute.class("section"),
                  attribute.style("margin-top", "20px"),
                ],
                [
                  html.h2([], [html.text("Quick Actions")]),
                  html.button(
                    [
                      attribute.id("refresh-games"),
                      attribute.class("btn btn-secondary"),
                    ],
                    [html.text("Refresh Games")],
                  ),
                  html.button(
                    [
                      attribute.id("leave-game"),
                      attribute.class("btn btn-secondary"),
                      attribute.style("margin-left", "10px"),
                    ],
                    [html.text("Leave Current Game")],
                  ),
                ],
              ),
            ]),
            html.div([attribute.class("section")], [
              html.h2([], [html.text("Available Games")]),
              html.div([attribute.id("current-game-info")], []),
              html.div(
                [attribute.id("games-list"), attribute.class("game-list")],
                [
                  html.p([attribute.style("color", "#718096")], [
                    html.text("Loading games..."),
                  ]),
                ],
              ),
            ]),
          ]),
          html.div([attribute.id("status"), attribute.class("status")], []),
        ]),
        html.script([attribute.src("/static/lobby.js")], ""),
      ]),
    ])
    |> element.to_document_string_tree

  case wisp.get_cookie(req, "glurve_user_id", wisp.PlainText) {
    Ok(_) -> {
      wisp.html_response(html, 200)
    }
    Error(_) -> {
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
  }
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
