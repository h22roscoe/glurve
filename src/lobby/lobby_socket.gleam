import gleam/erlang/process.{type Selector, type Subject}
import gleam/json
import gleam/option.{type Option, Some}
import glubsub
import lobby/lobby_manager.{type LobbyManagerMsg}
import lustre
import lustre/server_component
import mist

pub type LobbySocket {
  LobbySocket(
    component: lustre.Runtime(LobbyManagerMsg),
    subject: Subject(server_component.ClientMessage(LobbyManagerMsg)),
  )
}

pub type LobbySocketMessage =
  server_component.ClientMessage(LobbyManagerMsg)

pub type LobbySocketInit =
  #(LobbySocket, Option(Selector(LobbySocketMessage)))

pub fn init_lobby_socket(
  _,
  lobby_manager_subject: process.Subject(LobbySocketMessage),
) -> LobbySocketInit {
  let lobby_manager = lobby_manager.component()

  let assert Ok(component) = lustre.start_server_component(lobby_manager, Nil)

  let selector = process.new_selector() |> process.select(lobby_manager_subject)

  server_component.register_subject(lobby_manager_subject)
  |> lustre.send(to: component)

  #(LobbySocket(component:, subject: lobby_manager_subject), Some(selector))
}

pub fn loop_lobby_socket(
  state: LobbySocket,
  message: mist.WebsocketMessage(LobbySocketMessage),
  connection: mist.WebsocketConnection,
) -> mist.Next(LobbySocket, LobbySocketMessage) {
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
      server_component.deregister_subject(state.subject)
      |> lustre.send(to: state.component)

      mist.stop()
    }
  }
}

pub fn close_lobby_socket(state: LobbySocket) -> Nil {
  server_component.deregister_subject(state.subject)
  |> lustre.send(to: state.component)
}
