import player/player.{type TurnDirection}

pub type GameSharedMsg {
  PlayerCrashed(String)
  PlayerTurning(String, TurnDirection)
}
