import gleam/erlang/process.{type Subject}
import gleam/otp/actor.{type Started}
import lobby/lobby.{type LobbyMsg}

pub type LobbyManagerSharedMsg {
  LobbyCreated(name: String, lobby: Started(Subject(LobbyMsg)))
  LobbyRemoved(name: String)
}
