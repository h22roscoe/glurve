import app/app.{type AppMsg, type AppSharedMsg, StartArgs}
import gleam/erlang/process.{type Selector, type Subject}
import gleam/json
import gleam/option.{type Option, Some}
import glubsub.{type Topic}
import lustre
import lustre/server_component
import mist

pub type AppSocket {
  AppSocket(
    component: lustre.Runtime(AppMsg),
    self: Subject(server_component.ClientMessage(AppMsg)),
  )
}

pub type AppSocketMessage =
  server_component.ClientMessage(AppMsg)

pub type AppSocketInit =
  #(AppSocket, Option(Selector(AppSocketMessage)))

pub fn init(_, topic: Topic(AppSharedMsg)) -> AppSocketInit {
  let app = app.component()
  let assert Ok(component) =
    lustre.start_server_component(app, StartArgs(topic:))

  let self = process.new_subject()
  let selector = process.new_selector() |> process.select(self)

  server_component.register_subject(self)
  |> lustre.send(to: component)

  #(AppSocket(component:, self:), Some(selector))
}

pub fn loop_socket(
  state: AppSocket,
  message: mist.WebsocketMessage(AppSocketMessage),
  connection: mist.WebsocketConnection,
) -> mist.Next(AppSocket, AppSocketMessage) {
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

pub fn close_socket(state: AppSocket) -> Nil {
  server_component.deregister_subject(state.self)
  |> lustre.send(to: state.component)
}
