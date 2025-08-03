import game
import game_message.{type Msg}
import gleam/bytes_tree
import gleam/erlang/application
import gleam/erlang/process.{type Selector, type Subject}
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/json
import gleam/option.{type Option, None, Some}
import glubsub
import lustre
import lustre/attribute
import lustre/element
import lustre/element/html.{html}
import lustre/server_component
import mist.{type Connection, type ResponseData}

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let assert Ok(topic) = glubsub.new_topic()

  let assert Ok(_) =
    fn(request: Request(Connection)) -> Response(ResponseData) {
      case request.path_segments(request) {
        [] -> serve_html()
        ["lustre", "runtime.mjs"] -> serve_runtime()
        ["ws"] -> serve_game(request, topic)
        _ -> response.set_body(response.new(404), mist.Bytes(bytes_tree.new()))
      }
    }
    |> mist.new
    |> mist.bind("localhost")
    |> mist.port(1234)
    |> mist.start

  process.sleep_forever()
}

// HTML ------------------------------------------------------------------------

fn serve_html() -> Response(ResponseData) {
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
        server_component.element([server_component.route("/ws")], []),
      ]),
    ])
    |> element.to_document_string_tree
    |> bytes_tree.from_string_tree

  response.new(200)
  |> response.set_body(mist.Bytes(html))
  |> response.set_header("content-type", "text/html")
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
  topic: glubsub.Topic(game_message.SharedMsg),
) -> Response(ResponseData) {
  mist.websocket(
    request:,
    on_init: init_game_socket(_, topic),
    handler: loop_game_socket,
    on_close: close_game_socket,
  )
}

type GameSocket {
  GameSocket(
    component: lustre.Runtime(Msg),
    self: Subject(server_component.ClientMessage(Msg)),
  )
}

type GameSocketMessage =
  server_component.ClientMessage(Msg)

type GameSocketInit =
  #(GameSocket, Option(Selector(GameSocketMessage)))

fn init_game_socket(
  _,
  topic: glubsub.Topic(game_message.SharedMsg),
) -> GameSocketInit {
  let game = game.component()
  let assert Ok(component) = lustre.start_server_component(game, topic)

  let self = process.new_subject()
  let selector = process.new_selector() |> process.select(self)

  server_component.register_subject(self)
  |> lustre.send(to: component)

  #(GameSocket(component:, self:), Some(selector))
}

fn loop_game_socket(
  state: GameSocket,
  message: mist.WebsocketMessage(GameSocketMessage),
  connection: mist.WebsocketConnection,
) -> mist.Next(GameSocket, GameSocketMessage) {
  case message {
    mist.Text(json) -> {
      case json.parse(json, server_component.runtime_message_decoder()) {
        Ok(runtime_message) -> lustre.send(state.component, runtime_message)
        Error(_) -> Nil
      }

      mist.continue(state)
    }

    mist.Binary(_) -> {
      mist.continue(state)
    }

    mist.Custom(client_message) -> {
      let json = server_component.client_message_to_json(client_message)
      let assert Ok(_) = mist.send_text_frame(connection, json.to_string(json))

      mist.continue(state)
    }

    mist.Closed | mist.Shutdown -> {
      server_component.deregister_subject(state.self)
      |> lustre.send(to: state.component)

      mist.stop()
    }
  }
}

fn close_game_socket(state: GameSocket) -> Nil {
  server_component.deregister_subject(state.self)
  |> lustre.send(to: state.component)
}
