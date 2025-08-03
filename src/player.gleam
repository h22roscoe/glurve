import constants.{height, width}
import game_message.{type Msg}
import gleam/float
import gleam/int
import gleam/list
import gleam_community/maths
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/svg

const tail_radius = 3.0

const head_size = 10.0

const turn_rate = 0.05

// The number of tail segments to skip when checking for collision. This is to
// prevent the player from immediately colliding with their own tail.
const tail_collision_grace_segments = 50

pub type TurnDirection {
  Left
  Right
  Straight
}

pub type Player {
  Player(
    id: Int,
    x: Float,
    y: Float,
    speed: Float,
    angle: Float,
    tail: List(#(Float, Float)),
    turning: TurnDirection,
  )
}

pub fn check_collision(player: Player) -> Bool {
  let speed = player.speed
  let head_x = player.x
  let head_y = player.y
  let collision_distance = tail_radius +. tail_radius
  case speed {
    0.0 -> False
    _ ->
      player.tail
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

/// Returns a new player with the updated turning direction.
pub fn turn(player: Player, direction: TurnDirection) -> Player {
  Player(..player, turning: direction)
}

/// Returns a new player with the updated speed.
pub fn update_speed(player: Player, speed: Float) -> Player {
  Player(..player, speed: speed)
}

/// Returns a new player with the updated position and tail based on a game tick.
pub fn update(player: Player) -> Player {
  let angle = case player.turning {
    Left -> player.angle -. turn_rate
    Right -> player.angle +. turn_rate
    Straight -> player.angle
  }

  let new_x = player.x +. maths.cos(angle) *. player.speed
  let new_y = player.y +. maths.sin(angle) *. player.speed

  let wrapped_x = wrap(new_x, width)

  let wrapped_y = wrap(new_y, height)

  let new_tail = [#(player.x, player.y), ..player.tail]

  case player.speed {
    0.0 -> Player(..player, angle: angle)
    _ ->
      Player(..player, x: wrapped_x, y: wrapped_y, angle: angle, tail: new_tail)
  }
}

/// Draws the player by creating a list of SVG elements that represent
/// the player's head and tail. The first element of each tuple is a string
/// that is used as the key of the element in the list, so that we only rerender
/// new keyed elements.
pub fn draw(player: Player) -> List(#(String, Element(Msg))) {
  let tail_points =
    player.tail
    |> list.map(fn(pos) {
      let #(x, y) = pos
      svg.circle([
        attribute.attribute("cx", float.to_string(x)),
        attribute.attribute("cy", float.to_string(y)),
        attribute.attribute("r", float.to_string(tail_radius)),
        attribute.attribute("fill", "black"),
      ])
    })

  // Draw a triangle "head" at (player.x, player.y) facing player.angle
  let angle = player.angle

  // Calculate the three points of the triangle
  let tip_x = player.x +. maths.cos(angle) *. head_size
  let tip_y = player.y +. maths.sin(angle) *. head_size

  let left_angle = angle +. maths.pi() *. 2.0 /. 3.0
  let left_x = player.x +. maths.cos(left_angle) *. { head_size /. 1.5 }
  let left_y = player.y +. maths.sin(left_angle) *. { head_size /. 1.5 }

  let right_angle = angle -. maths.pi() *. 2.0 /. 3.0
  let right_x = player.x +. maths.cos(right_angle) *. { head_size /. 1.5 }
  let right_y = player.y +. maths.sin(right_angle) *. { head_size /. 1.5 }

  let points =
    float.to_string(tip_x)
    <> ","
    <> float.to_string(tip_y)
    <> " "
    <> float.to_string(left_x)
    <> ","
    <> float.to_string(left_y)
    <> " "
    <> float.to_string(right_x)
    <> ","
    <> float.to_string(right_y)

  let head =
    svg.polygon([
      attribute.attribute("points", points),
      attribute.attribute("fill", "black"),
    ])

  let head_keyed = #("head", head)

  let tail_points_len = list.length(tail_points)
  let tail_points_keyed =
    tail_points
    |> list.index_map(fn(pos, index) {
      #("tail-" <> int.to_string(tail_points_len - index - 1), pos)
    })

  [head_keyed, ..tail_points_keyed]
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
