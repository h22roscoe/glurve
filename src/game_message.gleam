pub type TimerID

@external(erlang, "timer", "cancel")
pub fn cancel(id: TimerID) -> Result(Nil, Nil)

@external(erlang, "timer", "apply_interval")
pub fn apply_interval(
  delay_ms: Int,
  callback: fn() -> any,
) -> Result(TimerID, String)

pub type Msg {
  NewTimer(TimerID)
  NewCountdownTimer(TimerID)
  StartGame
  CountdownTick
  Tick
  KeyDown(Int, String)
  KeyUp(Int, String)
  NoOp
}
