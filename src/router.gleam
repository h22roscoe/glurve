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
  case wisp.get_cookie(req, "glurve_user_id", wisp.Signed) {
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
  case wisp.get_cookie(request, "glurve_user_id", wisp.Signed) {
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
  case wisp.get_cookie(request, "glurve_user_id", wisp.Signed) {
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
  case wisp.get_cookie(request, "glurve_user_id", wisp.Signed) {
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
        html.style(
          [],
          "
          * { margin: 0; padding: 0; box-sizing: border-box; }
          body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
          }
          .container { 
            max-width: 1200px; 
            margin: 0 auto; 
            background: white; 
            border-radius: 12px; 
            box-shadow: 0 10px 30px rgba(0,0,0,0.2);
            overflow: hidden;
          }
          .header { 
            background: #4a5568; 
            color: white; 
            padding: 20px; 
            text-align: center; 
          }
          .content { 
            padding: 30px; 
            display: grid; 
            grid-template-columns: 1fr 1fr; 
            gap: 30px; 
          }
          .section { 
            background: #f7fafc; 
            padding: 20px; 
            border-radius: 8px; 
            border: 1px solid #e2e8f0; 
          }
          .section h2 { 
            color: #2d3748; 
            margin-bottom: 15px; 
            font-size: 1.2em; 
          }
          .form-group { 
            margin-bottom: 15px; 
          }
          .form-group label { 
            display: block; 
            margin-bottom: 5px; 
            color: #4a5568; 
            font-weight: 500; 
          }
          .form-group input { 
            width: 100%; 
            padding: 10px; 
            border: 1px solid #cbd5e0; 
            border-radius: 4px; 
            font-size: 14px; 
          }
          .btn { 
            background: #667eea; 
            color: white; 
            border: none; 
            padding: 10px 20px; 
            border-radius: 4px; 
            cursor: pointer; 
            font-size: 14px; 
            transition: background 0.2s; 
          }
          .btn:hover { 
            background: #5a67d8; 
          }
          .btn-secondary { 
            background: #718096; 
          }
          .btn-secondary:hover { 
            background: #4a5568; 
          }
          .game-list { 
            max-height: 300px; 
            overflow-y: auto; 
          }
          .game-item { 
            padding: 12px; 
            border: 1px solid #e2e8f0; 
            border-radius: 4px; 
            margin-bottom: 8px; 
            background: white; 
            display: flex; 
            justify-content: space-between; 
            align-items: center; 
          }
          .game-info h3 { 
            color: #2d3748; 
            font-size: 1em; 
            margin-bottom: 4px; 
          }
          .game-info p { 
            color: #718096; 
            font-size: 0.9em; 
          }
          .current-game { 
            background: #c6f6d5; 
            border-color: #68d391; 
          }
          .status { 
            margin-top: 20px; 
            padding: 15px; 
            border-radius: 4px; 
            display: none; 
          }
          .status.success { 
            background: #c6f6d5; 
            color: #22543d; 
            border: 1px solid #68d391; 
          }
          .status.error { 
            background: #fed7d7; 
            color: #742a2a; 
            border: 1px solid #fc8181; 
          }
          @media (max-width: 768px) {
            .content { 
              grid-template-columns: 1fr; 
              gap: 20px; 
            }
          }
        ",
        ),
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
        html.script(
          [],
          "
          let currentGameId = null;
          
          // Load games and current player game on page load
          document.addEventListener('DOMContentLoaded', () => {
            loadGames();
            loadCurrentPlayerGame();
          });
          
          // Create game form handler
          document.getElementById('create-form').addEventListener('submit', async (e) => {
            e.preventDefault();
            const gameName = document.getElementById('game-name').value;
            
            try {
              const response = await fetch(`/create-game/${encodeURIComponent(gameName)}`, {
                method: 'GET'
              });
              
              if (response.ok) {
                const game = await response.json();
                showStatus(`Game '${game.name}' created successfully!`, 'success');
                document.getElementById('game-name').value = '';
                loadGames();
                loadCurrentPlayerGame();
              } else {
                showStatus('Failed to create game', 'error');
              }
            } catch (error) {
              showStatus('Error creating game', 'error');
            }
          });
          
          // Refresh games button
          document.getElementById('refresh-games').addEventListener('click', () => {
            loadGames();
            loadCurrentPlayerGame();
          });
          
          // Leave game button
          document.getElementById('leave-game').addEventListener('click', async () => {
            try {
              const response = await fetch('/leave-game', { method: 'GET' });
              if (response.ok) {
                showStatus('Left game successfully', 'success');
                loadGames();
                loadCurrentPlayerGame();
              } else {
                showStatus('Failed to leave game', 'error');
              }
            } catch (error) {
              showStatus('Error leaving game', 'error');
            }
          });
          
          // Load available games
          async function loadGames() {
            try {
              const response = await fetch('/list-games');
              const games = await response.json();
              
              const gamesList = document.getElementById('games-list');
              
              if (games.length === 0) {
                gamesList.innerHTML = '<p style=\"color: #718096\">No games available. Create one!</p>';
                return;
              }
              
              gamesList.innerHTML = games.map(game => `
                <div class=\"game-item\">
                  <div class=\"game-info\">
                    <h3>${game.name}</h3>
                    <p>Players: ${game.player_count}/${game.max_players} • Status: ${game.status}</p>
                  </div>
                  <button class=\"btn\" onclick=\"joinGame('${game.id}')\">Join</button>
                </div>
              `).join('');
            } catch (error) {
              document.getElementById('games-list').innerHTML = '<p style=\"color: #e53e3e\">Error loading games</p>';
            }
          }
          
          // Load current player game
          async function loadCurrentPlayerGame() {
            try {
              const response = await fetch('/get-player-game');
              const game = await response.json();
              
              const currentGameInfo = document.getElementById('current-game-info');
              
              if (game) {
                currentGameId = game.id;
                currentGameInfo.innerHTML = `
                  <div class=\"game-item current-game\">
                    <div class=\"game-info\">
                      <h3>🎯 Current Game: ${game.name}</h3>
                      <p>Players: ${game.player_count}/${game.max_players} • Status: ${game.status}</p>
                    </div>
                    <button class=\"btn\" onclick=\"enterGame('${game.id}')\">Enter Game</button>
                  </div>
                `;
              } else {
                currentGameId = null;
                currentGameInfo.innerHTML = '';
              }
            } catch (error) {
              console.error('Error loading current player game:', error);
            }
          }
          
          // Join a game
          async function joinGame(gameId) {
            try {
              const response = await fetch(`/join-game/${gameId}`, { method: 'GET' });
              
              if (response.ok) {
                const game = await response.json();
                showStatus(`Joined game '${game.name}'!`, 'success');
                loadGames();
                loadCurrentPlayerGame();
              } else {
                showStatus('Failed to join game', 'error');
              }
            } catch (error) {
              showStatus('Error joining game', 'error');
            }
          }
          
          // Enter a game (navigate to game page)
          function enterGame(gameId) {
            window.location.href = `/game/${gameId}`;
          }
          
          // Show status message
          function showStatus(message, type) {
            const status = document.getElementById('status');
            status.textContent = message;
            status.className = `status ${type}`;
            status.style.display = 'block';
            
            setTimeout(() => {
              status.style.display = 'none';
            }, 5000);
          }
          
          // Auto-refresh games every 5 seconds
          setInterval(() => {
            loadGames();
            loadCurrentPlayerGame();
          }, 5000);
        ",
        ),
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
