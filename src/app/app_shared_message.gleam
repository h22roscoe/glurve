import game/game_shared_message.{type GameSharedMsg}
import lobby/lobby_manager_shared_message.{type LobbyManagerSharedMsg}
import lobby/lobby_shared_message.{type LobbySharedMsg}

pub type AppSharedMsg {
  RecievedLobbyManagerMsg(LobbyManagerSharedMsg)
  RecievedLobbyMsg(LobbySharedMsg)
  RecievedGameMsg(GameSharedMsg)
}
