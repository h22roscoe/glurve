import position.{type Position}

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
  NewTimer(TimerID)
  NewCountdownTimer(TimerID)
  StartGame
  CountdownTick
  Tick
  KeyDown(String)
  KeyUp(String)
  NoOp
}

pub type SharedMsg {
  ClientPlayerMoved(String, Position, Float)
}
