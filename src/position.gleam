import constants.{height, width}
import gleam/int
import gleam/yielder.{type Yielder}
import prng/random.{type Generator}
import prng/seed

pub type Position {
  Position(x: Float, y: Float)
}

pub fn random_start_position() -> Yielder(Position) {
  let initial_seed = seed.new(1)
  let width_generator: Generator(Int) = random.int(0, width - 1)
  let height_generator: Generator(Int) = random.int(0, height - 1)
  let width_yielder = random.to_yielder(width_generator, initial_seed)
  let height_yielder = random.to_yielder(height_generator, initial_seed)

  yielder.map2(width_yielder, height_yielder, fn(x, y) {
    Position(x: int.to_float(x), y: int.to_float(y))
  })
}
