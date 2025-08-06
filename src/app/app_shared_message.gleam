import lobby/lobby_manager_shared_message.{type LobbyManagerSharedMsg}
import lobby/lobby_shared_message.{type LobbySharedMsg}

pub type AppSharedMsg {
  LobbyManagerSharedMsg(LobbyManagerSharedMsg)
  LobbySharedMsg(LobbySharedMsg)
}
