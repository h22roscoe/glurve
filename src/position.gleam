import constants.{height, width}
import gleam/int
import prng/random.{type Generator}
import prng/seed

pub type Position {
  Position(x: Float, y: Float)
}

pub fn random_start_position() -> Position {
  let width_generator: Generator(Int) = random.int(0, width - 1)
  let height_generator: Generator(Int) = random.int(0, height - 1)

  Position(
    x: int.to_float(random.sample(width_generator, seed.new(1))),
    y: int.to_float(random.sample(height_generator, seed.new(1))),
  )
}
