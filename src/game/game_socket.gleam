import game/game.{type GameMsg}
import game/game_shared_message
import gleam/dict
import gleam/erlang/process.{type Selector, type Subject}
import gleam/json
import gleam/option.{type Option, Some}
import glubsub
import lustre
import lustre/server_component
import mist
import player/player
import prng/seed.{type Seed}

pub type GameSocket {
  GameSocket(
    component: lustre.Runtime(GameMsg),
    self: Subject(server_component.ClientMessage(GameMsg)),
  )
}

pub type GameSocketMessage =
  server_component.ClientMessage(GameMsg)

pub type GameSocketInit =
  #(GameSocket, Option(Selector(GameSocketMessage)))

pub fn init(
  _,
  id: String,
  topic: glubsub.Topic(game_shared_message.GameSharedMsg),
  players: dict.Dict(String, player.Player),
  seed: Seed,
) -> GameSocketInit {
  let game = game.component()

  let assert Ok(component) =
    lustre.start_server_component(
      game,
      game.StartArgs(id:, topic:, players:, seed:),
    )

  let self = process.new_subject()
  let selector = process.new_selector() |> process.select(self)

  server_component.register_subject(self)
  |> lustre.send(to: component)

  #(GameSocket(component:, self:), Some(selector))
}

pub fn loop_socket(
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

pub fn close_socket(state: GameSocket) -> Nil {
  server_component.deregister_subject(state.self)
  |> lustre.send(to: state.component)
}
