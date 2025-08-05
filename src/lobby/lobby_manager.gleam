import gleam/erlang/process
import gleam/otp/actor
import lobby/lobby.{type LobbyMsg}

pub fn start() -> actor.Started(process.Subject(LobbyManagerMsg)) {
  let state = []
  let assert Ok(actor) =
    actor.new(state)
    |> actor.on_message(handle_lobby_manager_msg)
    |> actor.start()
  actor
}

pub opaque type LobbyManagerMsg {
  CreateLobby(
    name: String,
    max_players: Int,
    reply_with: process.Subject(actor.Started(process.Subject(LobbyMsg))),
  )
  ListLobbies(
    reply_with: process.Subject(List(actor.Started(process.Subject(LobbyMsg)))),
  )
}

fn handle_lobby_manager_msg(
  state: List(actor.Started(process.Subject(LobbyMsg))),
  msg: LobbyManagerMsg,
) -> actor.Next(List(actor.Started(process.Subject(LobbyMsg))), LobbyManagerMsg) {
  case msg {
    CreateLobby(name, max_players, reply_with) -> {
      let lobby = lobby.start(name, max_players)
      process.send(reply_with, lobby)
      actor.continue([lobby, ..state])
    }
    ListLobbies(reply_with) -> {
      process.send(reply_with, state)
      actor.continue(state)
    }
  }
}

pub fn create_lobby(
  subject: process.Subject(LobbyManagerMsg),
  name: String,
  max_players: Int,
) -> actor.Started(process.Subject(LobbyMsg)) {
  process.call(subject, 1000, CreateLobby(name, max_players, _))
}

pub fn list_lobbies(
  subject: process.Subject(LobbyManagerMsg),
) -> List(actor.Started(process.Subject(LobbyMsg))) {
  process.call(subject, 1000, ListLobbies)
}
