import gleam/dict
import gleam/erlang/process
import gleam/otp/actor
import glubsub
import lobby/lobby.{type LobbyMsg}

pub fn start() -> actor.Started(process.Subject(LobbyManagerMsg)) {
  let assert Ok(topic) = glubsub.new_topic()
  let state = LobbyManagerState(lobbies: dict.new(), topic: topic)
  let assert Ok(actor) =
    actor.new(state)
    |> actor.on_message(handle_lobby_manager_msg)
    |> actor.start()
  actor
}

pub opaque type LobbyManagerState {
  LobbyManagerState(
    lobbies: dict.Dict(String, actor.Started(process.Subject(LobbyMsg))),
    topic: glubsub.Topic(LobbyManagerSharedMsg),
  )
}

pub opaque type LobbyManagerSharedMsg {
  LobbyCreated(name: String, lobby: actor.Started(process.Subject(LobbyMsg)))
  LobbyRemoved(name: String)
}

pub type LobbyManagerMsg {
  CreateLobby(name: String, max_players: Int)
  RemoveLobby(name: String)
  ListLobbies(
    reply_with: process.Subject(
      dict.Dict(String, actor.Started(process.Subject(LobbyMsg))),
    ),
  )
}

fn handle_lobby_manager_msg(
  state: LobbyManagerState,
  msg: LobbyManagerMsg,
) -> actor.Next(LobbyManagerState, LobbyManagerMsg) {
  case msg {
    CreateLobby(name, max_players) -> {
      let lobby = lobby.start(name, max_players)
      let assert Ok(_) =
        glubsub.broadcast(state.topic, LobbyCreated(name, lobby))
      actor.continue(
        LobbyManagerState(
          ..state,
          lobbies: dict.insert(state.lobbies, name, lobby),
        ),
      )
    }
    RemoveLobby(name) -> {
      let new_lobbies = dict.delete(state.lobbies, name)
      let assert Ok(_) = glubsub.broadcast(state.topic, LobbyRemoved(name))
      actor.continue(LobbyManagerState(..state, lobbies: new_lobbies))
    }
    ListLobbies(reply_with) -> {
      process.send(reply_with, state.lobbies)
      actor.continue(state)
    }
  }
}

pub fn create_lobby(
  subject: process.Subject(LobbyManagerMsg),
  name: String,
  max_players: Int,
) -> Nil {
  process.send(subject, CreateLobby(name, max_players))
}

pub fn list_lobbies(
  subject: process.Subject(LobbyManagerMsg),
) -> dict.Dict(String, actor.Started(process.Subject(LobbyMsg))) {
  process.call(subject, 1000, ListLobbies)
}
