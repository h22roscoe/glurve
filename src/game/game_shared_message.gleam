import player/player.{type TurnDirection}

pub type GameSharedMsg {
  PlayerJoined(String)
  ExistingPlayer(String)
  PlayerCrashed(String)
  StartedGame
  PlayerTurning(String, TurnDirection)
}
