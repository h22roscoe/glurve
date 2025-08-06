import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/otp/actor.{type Started}
import glubsub.{type Topic}
import lobby/lobby.{type LobbyMsg}
import shared_messages.{
  type AppSharedMsg, LobbyCreated, LobbyManagerSharedMsg, LobbyRemoved,
}

pub fn start(
  topic: Topic(AppSharedMsg(LobbyMsg)),
) -> actor.Started(process.Subject(LobbyManagerMsg)) {
  let state = LobbyManagerState(lobbies: dict.new(), topic: topic)
  let assert Ok(actor) =
    actor.new(state)
    |> actor.on_message(handle_lobby_manager_msg)
    |> actor.start()
  actor
}

pub opaque type LobbyManagerState {
  LobbyManagerState(
    lobbies: dict.Dict(String, Started(Subject(LobbyMsg))),
    topic: glubsub.Topic(AppSharedMsg(LobbyMsg)),
  )
}

pub type LobbyManagerMsg {
  CreateLobby(name: String, max_players: Int)
  RemoveLobby(name: String)
  ListLobbies(
    reply_with: Subject(dict.Dict(String, Started(Subject(LobbyMsg)))),
  )
}

fn handle_lobby_manager_msg(
  state: LobbyManagerState,
  msg: LobbyManagerMsg,
) -> actor.Next(LobbyManagerState, LobbyManagerMsg) {
  case msg {
    CreateLobby(name, max_players) -> {
      let lobby = lobby.start(name, max_players, state.topic)
      let assert Ok(_) =
        glubsub.broadcast(
          state.topic,
          LobbyCreated(name, lobby) |> LobbyManagerSharedMsg,
        )
      actor.continue(
        LobbyManagerState(
          ..state,
          lobbies: dict.insert(state.lobbies, name, lobby),
        ),
      )
    }
    RemoveLobby(name) -> {
      let new_lobbies = dict.delete(state.lobbies, name)
      let assert Ok(_) =
        glubsub.broadcast(
          state.topic,
          LobbyRemoved(name) |> LobbyManagerSharedMsg,
        )
      actor.continue(LobbyManagerState(..state, lobbies: new_lobbies))
    }
    ListLobbies(reply_with) -> {
      process.send(reply_with, state.lobbies)
      actor.continue(state)
    }
  }
}

pub fn create_lobby(
  subject: Subject(LobbyManagerMsg),
  name: String,
  max_players: Int,
) -> Nil {
  process.send(subject, CreateLobby(name, max_players))
}

pub fn remove_lobby(subject: Subject(LobbyManagerMsg), name: String) -> Nil {
  process.send(subject, RemoveLobby(name))
}

pub fn list_lobbies(
  subject: Subject(LobbyManagerMsg),
) -> dict.Dict(String, Started(Subject(LobbyMsg))) {
  process.call(subject, 1000, ListLobbies)
}

pub fn get_lobby(
  subject: Subject(LobbyManagerMsg),
  lobby_id: String,
) -> Started(Subject(LobbyMsg)) {
  let lobbies = list_lobbies(subject)
  let assert Ok(lobby) = dict.get(lobbies, lobby_id)
  lobby
}
