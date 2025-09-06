import gleam/erlang/process.{type Subject}
import gleam/otp/actor.{type Started}
import player/colour

pub type AppSharedMsg(m) {
  LobbyManagerSharedMsg(LobbyManagerSharedMsg(m))
  LobbySharedMsg(LobbySharedMsg)
  GameLifecycleSharedMsg(GameLifecycleSharedMsg)
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
  PlayerIsChangingColour(player_id: String)
  PlayerHasPickedColour(player_id: String, colour: colour.Colour)
  AllPlayersReady
  PlayerExitedGame(player_id: String)
  LobbyClosed
}

pub type GameLifecycleSharedMsg {
  RoundEnded
}
