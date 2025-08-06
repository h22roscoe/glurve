import gleam/erlang/process.{type Subject}
import gleam/otp/actor.{type Started}

pub type AppSharedMsg(m) {
  LobbyManagerSharedMsg(LobbyManagerSharedMsg(m))
  LobbySharedMsg(LobbySharedMsg)
}

pub type LobbyManagerSharedMsg(m) {
  LobbyCreated(name: String, lobby: Started(Subject(m)))
  LobbyRemoved(name: String)
}

pub type LobbySharedMsg {
  LobbyJoined(player_id: String, lobby_id: String)
  LobbyLeft(player_id: String)
  PlayerBecameReady(player_id: String)
  PlayerBecameNotReady(player_id: String)
  AllPlayersReady
  LobbyClosed
}
