import player/player.{type TurnDirection}

pub type TimerID

@external(erlang, "timer", "cancel")
pub fn cancel(id: TimerID) -> Result(Nil, Nil)

@external(erlang, "timer", "apply_interval")
pub fn apply_interval(
  delay_ms: Int,
  callback: fn() -> any,
) -> Result(TimerID, String)

pub type Msg {
  RecievedSharedMsg(SharedMsg)
  KickOffGame
  NewTimer(TimerID)
  NewCountdownTimer(TimerID)
  CountdownTick
  Tick
  KeyDown(String)
  KeyUp(String)
  NoOp
}

pub type SharedMsg {
  PlayerJoined(String)
  ExistingPlayer(String)
  PlayerCrashed(String)
  StartedGame
  PlayerTurning(String, TurnDirection)
}
