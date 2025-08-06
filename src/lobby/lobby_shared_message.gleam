pub type LobbySharedMsg {
  LobbyJoined(player_id: String)
  LobbyLeft(player_id: String)
  PlayerBecameReady(player_id: String)
  PlayerBecameNotReady(player_id: String)
  AllPlayersReady
  LobbyClosed
}
