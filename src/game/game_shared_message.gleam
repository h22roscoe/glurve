import player/player.{type TurnDirection}

pub type GameSharedMsg {
  PlayerCrashed(String)
  StartedGame
  PlayerTurning(String, TurnDirection)
}
