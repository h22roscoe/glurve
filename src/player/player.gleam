import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/string
import gleam_community/maths
import lustre/attribute
import lustre/element
import lustre/element/svg
import player/colour
import position.{type Position}
import prng/random
import prng/seed

pub const tail_radius = 3.0

const turn_rate = 0.05

// The number of tail segments to skip when checking for collision. This is to
// prevent the player from immediately colliding with their own tail.
const tail_collision_grace_segments = 50

pub type TurnDirection {
  Left
  Right
  Straight
  Facing(x: Float, y: Float)
}

pub type GapState {
  Gapping(until_tick: Int)
  Solid(next_gap_tick: Int)
}

pub type Player {
  Player(
    id: String,
    colour: colour.Colour,
    position: Position,
    speed: Float,
    angle: Float,
    tail: List(List(#(Float, Float))),
    turning: TurnDirection,
    seed: seed.Seed,
    gap_state: GapState,
  )
}

pub fn check_collision_with_self(player: Player) -> Bool {
  let speed = player.speed
  let head_x = player.position.x
  let head_y = player.position.y
  let collision_distance = tail_radius +. tail_radius
  case speed {
    0.0 -> False
    _ ->
      player.tail
      |> list.flatten()
      |> list.drop(tail_collision_grace_segments)
      |> list.any(fn(pos) {
        let #(tail_x, tail_y) = pos
        let dx = head_x -. tail_x
        let dy = head_y -. tail_y
        let distance_squared = dx *. dx +. dy *. dy
        distance_squared <. collision_distance *. collision_distance
      })
  }
}

pub fn check_collision_with_edges(
  player: Player,
  height: Int,
  width: Int,
) -> Bool {
  let head_x = player.position.x
  let head_y = player.position.y
  head_x <=. 0.0
  || head_x >=. int.to_float(width)
  || head_y <=. 0.0
  || head_y >=. int.to_float(height)
}

pub fn check_collision_with_other_players(
  player: Player,
  players: dict.Dict(String, Player),
) -> Bool {
  let other_players = dict.delete(players, player.id)
  let other_players_list =
    dict.to_list(other_players)
    |> list.map(fn(e) {
      let #(_, p) = e
      p
    })
  // Check if any of the points in the tails of the other players are colliding with this player
  list.any(other_players_list, fn(p) {
    let dx = player.position.x -. p.position.x
    let dy = player.position.y -. p.position.y
    let distance_squared = dx *. dx +. dy *. dy
    let head_on_collision = distance_squared <. tail_radius *. tail_radius
    let tail_collision =
      p.tail
      |> list.flatten()
      |> list.any(fn(pos) {
        let #(tail_x, tail_y) = pos
        let dx = player.position.x -. tail_x
        let dy = player.position.y -. tail_y
        let distance_squared = dx *. dx +. dy *. dy
        distance_squared <. tail_radius *. tail_radius
      })
    head_on_collision || tail_collision
  })
}

/// Returns a new player with the updated turning direction.
pub fn turn(player: Player, direction: TurnDirection) -> Player {
  Player(..player, turning: direction)
}

/// Returns a new player with the updated speed.
pub fn update_speed(player: Player, speed: Float) -> Player {
  Player(..player, speed: speed)
}

fn normalize_angle(a: Float) -> Float {
  // Maps to [-pi, pi]
  maths.atan2(maths.sin(a), maths.cos(a))
}

/// A random generator that produces the number of ticks the gap should be gapping for.
fn gap_for_generator() -> random.Generator(Int) {
  random.int(30, 80)
}

/// A random generator that produces the number of ticks until the next gap.
fn solid_for_generator() -> random.Generator(Int) {
  random.int(150, 500)
}

fn advance_gap_state(
  gap_state: GapState,
  seed: seed.Seed,
  tick: Int,
) -> #(GapState, seed.Seed) {
  case gap_state {
    Gapping(until_tick) ->
      case tick >= until_tick {
        True -> {
          let #(solid_for, next_seed) = random.step(solid_for_generator(), seed)
          #(Solid(tick + solid_for), next_seed)
        }
        False -> #(gap_state, seed)
      }
    Solid(next_gap_tick) ->
      case tick >= next_gap_tick {
        True -> {
          let #(gap_for, next_seed) = random.step(gap_for_generator(), seed)
          #(Gapping(tick + gap_for), next_seed)
        }
        False -> #(gap_state, seed)
      }
  }
}

/// Returns a new player with the updated position and tail based on a game tick.
pub fn update(player: Player, tick: Int, height: Int, width: Int) -> Player {
  let angle = case player.turning {
    Left -> player.angle -. turn_rate
    Right -> player.angle +. turn_rate
    Straight -> player.angle
    Facing(x, y) -> {
      let dx = x *. int.to_float(width) -. player.position.x
      let dy = y *. int.to_float(height) -. player.position.y

      // If we're basically at the target, don't change angle
      let dist2 = { dx *. dx } +. { dy *. dy }
      case dist2 <. 1.0e-12 {
        True -> player.angle
        False -> {
          let fx = maths.cos(player.angle)
          let fy = maths.sin(player.angle)

          let cross = fx *. dy -. fy *. dx
          let dot = fx *. dx +. fy *. dy

          // Smallest signed angle from forward to target in [-pi, pi]
          let delta = maths.atan2(cross, dot)
          let step = float.clamp(delta, float.negate(turn_rate), turn_rate)
          normalize_angle(player.angle +. step)
        }
      }
    }
  }

  let new_x = player.position.x +. maths.cos(angle) *. player.speed
  let new_y = player.position.y +. maths.sin(angle) *. player.speed

  let wrapped_x = wrap(new_x, width)

  let wrapped_y = wrap(new_y, height)

  let #(gap_state, next_seed) =
    advance_gap_state(player.gap_state, player.seed, tick)

  // Build the tail based on the NEW gap_state. We want to:
  // - Add points while Solid is active
  // - Start a NEW segment when transitioning from Gapping -> Solid
  // - Do NOTHING while Gapping
  let new_tail = case gap_state {
    // While gapping we don't draw
    Gapping(_) -> player.tail

    // While solid we either continue the current segment or start a new one
    Solid(_) ->
      case player.gap_state {
        // Stayed solid: add the current head position to the current segment
        Solid(_) ->
          case player.tail {
            [head, ..rest] -> {
              let new_head = [#(player.position.x, player.position.y), ..head]
              [new_head, ..rest]
            }
            [] -> [[#(player.position.x, player.position.y)]]
          }

        // Transitioned from gapping -> solid: start a NEW segment at current position
        Gapping(_) -> [[#(player.position.x, player.position.y)], ..player.tail]
      }
  }

  case player.speed {
    0.0 -> Player(..player, angle: angle)
    _ ->
      Player(
        ..player,
        gap_state: gap_state,
        seed: next_seed,
        position: position.Position(x: wrapped_x, y: wrapped_y),
        angle: angle,
        tail: new_tail,
      )
  }
}

fn wrap(value: Float, max: Int) -> Float {
  let maxf = int.to_float(max)
  case value >. maxf {
    True -> 0.0
    False ->
      case value <. 0.0 {
        True -> maxf
        False -> value
      }
  }
}

pub fn to_svg_head(
  colour: colour.Colour,
  tip_x: Float,
  tip_y: Float,
  left_x: Float,
  left_y: Float,
  right_x: Float,
  right_y: Float,
) -> element.Element(a) {
  // Source triangle in the asset (viewBox 0 0 100 100):
  // tip=(90,50), left=(20,10), right=(20,90)
  let p0x = 90.0
  let p0y = 50.0
  let p1x = 20.0
  let p1y = 10.0
  let p2x = 20.0
  let p2y = 90.0

  let m00 = p1x -. p0x
  let m01 = p2x -. p0x
  let m10 = p1y -. p0y
  let m11 = p2y -. p0y
  let det = m00 *. m11 -. m01 *. m10

  // Inverse of M
  let inv00 = m11 /. det
  let inv01 = 0.0 -. m01 /. det
  let inv10 = 0.0 -. m10 /. det
  let inv11 = m00 /. det

  let n00 = left_x -. tip_x
  let n01 = right_x -. tip_x
  let n10 = left_y -. tip_y
  let n11 = right_y -. tip_y

  // A = N * inv(M)
  let a = n00 *. inv00 +. n01 *. inv10
  let c = n00 *. inv01 +. n01 *. inv11
  let b = n10 *. inv00 +. n11 *. inv10
  let d = n10 *. inv01 +. n11 *. inv11

  // t = Q0 - A * P0
  let e = tip_x -. a *. p0x -. c *. p0y
  let f = tip_y -. b *. p0x -. d *. p0y

  let matrix =
    "matrix("
    <> float.to_string(a)
    <> " "
    <> float.to_string(b)
    <> " "
    <> float.to_string(c)
    <> " "
    <> float.to_string(d)
    <> " "
    <> float.to_string(e)
    <> " "
    <> float.to_string(f)
    <> ")"

  let href = colour.to_svg_head_href(colour)

  svg.image([
    attribute.attribute("href", href),
    attribute.attribute("width", "100"),
    attribute.attribute("height", "100"),
    attribute.attribute("transform", matrix),
  ])
}

pub fn tail_polyline(
  points: List(#(Float, Float)),
  colour: colour.Colour,
) -> element.Element(a) {
  let coords =
    points
    |> list.map(fn(coord) {
      let #(x, y) = coord
      float.to_string(x) <> "," <> float.to_string(y)
    })
    |> string.join(" ")

  svg.polyline([
    colour.to_tail_styles(colour),
    attribute.attribute("points", coords),
    attribute.attribute(
      "stroke-width",
      float.round(tail_radius) |> int.to_string(),
    ),
    attribute.attribute("fill", "none"),
    attribute.attribute("stroke-linecap", "round"),
    attribute.attribute("stroke-linejoin", "round"),
  ])
}
