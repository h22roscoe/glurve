import gleam/dict
import gleam/int
import gleam/list
import gleam_community/colour
import gleam_community/maths
import position.{type Position}

pub const tail_radius = 3.0

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
    id: String,
    colour: colour.Colour,
    position: Position,
    speed: Float,
    angle: Float,
    tail: List(#(Float, Float)),
    turning: TurnDirection,
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
      list.any(p.tail, fn(pos) {
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

/// Returns a new player with the updated position and tail based on a game tick.
pub fn update(player: Player, height: Int, width: Int) -> Player {
  let angle = case player.turning {
    Left -> player.angle -. turn_rate
    Right -> player.angle +. turn_rate
    Straight -> player.angle
  }

  let new_x = player.position.x +. maths.cos(angle) *. player.speed
  let new_y = player.position.y +. maths.sin(angle) *. player.speed

  let wrapped_x = wrap(new_x, width)

  let wrapped_y = wrap(new_y, height)

  let new_tail = [#(player.position.x, player.position.y), ..player.tail]

  case player.speed {
    0.0 -> Player(..player, angle: angle)
    _ ->
      Player(
        ..player,
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
