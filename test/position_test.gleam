import gleam/yielder
import position

pub fn yields_different_positions_test() {
  let assert [position1, position2, ..] =
    yielder.take(position.random_start_position(), 2) |> yielder.to_list()
  assert position2.x != position1.x
  assert position2.y != position1.y
}
