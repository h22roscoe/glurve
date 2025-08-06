import gleam/int
import prng/random
import prng/seed.{type Seed}

pub type Position {
  Position(x: Float, y: Float)
}

fn sensible_start_positions(height: Int, width: Int) -> List(Position) {
  let fheight = int.to_float(height)
  let fwidth = int.to_float(width)
  [
    Position(x: fheight /. 2.0, y: fwidth /. 2.0),
    Position(x: fheight /. 2.0, y: 2.0 *. fwidth /. 3.0),
    Position(x: fheight /. 3.0, y: fwidth /. 2.0),
    Position(x: fheight /. 3.0, y: fwidth /. 3.0),
    Position(x: 2.0 *. fheight /. 3.0, y: fwidth /. 4.0),
    Position(x: 2.0 *. fheight /. 3.0, y: 3.0 *. fwidth /. 4.0),
    Position(x: fheight /. 4.0, y: 3.0 *. fwidth /. 4.0),
    Position(x: 3.0 *. fheight /. 4.0, y: fwidth /. 4.0),
  ]
}

pub fn random_start_position(
  height: Int,
  width: Int,
  seed: Seed,
) -> #(Position, Seed) {
  let sensible_positions = sensible_start_positions(height, width)
  let fheight = int.to_float(height)
  let fwidth = int.to_float(width)
  let option_generator =
    random.uniform(
      Position(x: fheight *. 2.0 /. 5.0, y: fwidth *. 2.0 /. 5.0),
      sensible_positions,
    )

  random.step(option_generator, seed)
}

pub fn random_start_positions(
  num_positions: Int,
  height: Int,
  width: Int,
  seed: Seed,
) -> #(List(Position), Seed) {
  case num_positions {
    0 -> #([], seed)
    _ -> {
      let #(positions, next_seed) =
        random_start_positions(num_positions - 1, height, width, seed)
      let #(position, next_next_seed) =
        random_start_position(height, width, next_seed)
      #([position, ..positions], next_next_seed)
    }
  }
}
