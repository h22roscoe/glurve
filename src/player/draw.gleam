import game/game_message.{type GameMsg}
import gleam/float
import gleam/int
import gleam/list
import gleam_community/colour
import gleam_community/maths
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/svg
import player/player.{tail_radius}

const head_size = 10.0

/// Draws the player by creating a list of SVG elements that represent
/// the player's head and tail. The first element of each tuple is a string
/// that is used as the key of the element in the list, so that we only rerender
/// new keyed elements.
pub fn draw_player(player: player.Player) -> List(#(String, Element(GameMsg))) {
  let colour = player.colour
  let tail_points =
    player.tail
    |> list.map(fn(pos) {
      let #(x, y) = pos
      svg.circle([
        attribute.attribute("cx", float.to_string(x)),
        attribute.attribute("cy", float.to_string(y)),
        attribute.attribute("r", float.to_string(tail_radius)),
        attribute.attribute("fill", colour.to_css_rgba_string(colour)),
        attribute.attribute("stroke", "black"),
        attribute.attribute("stroke-width", "0.02"),
      ])
    })

  // Draw a triangle "head" at (player.x, player.y) facing player.angle
  let angle = player.angle

  // Calculate the three points of the triangle
  let tip_x = player.position.x +. maths.cos(angle) *. head_size
  let tip_y = player.position.y +. maths.sin(angle) *. head_size

  let left_angle = angle +. maths.pi() *. 2.0 /. 3.0
  let left_x =
    player.position.x +. maths.cos(left_angle) *. { head_size /. 1.5 }
  let left_y =
    player.position.y +. maths.sin(left_angle) *. { head_size /. 1.5 }

  let right_angle = angle -. maths.pi() *. 2.0 /. 3.0
  let right_x =
    player.position.x +. maths.cos(right_angle) *. { head_size /. 1.5 }
  let right_y =
    player.position.y +. maths.sin(right_angle) *. { head_size /. 1.5 }

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
      attribute.attribute("fill", colour.to_css_rgba_string(colour)),
      attribute.attribute("stroke", "black"),
      attribute.attribute("stroke-width", "0.1"),
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
