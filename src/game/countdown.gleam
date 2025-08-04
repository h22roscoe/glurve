import game/game_message.{type GameMsg}
import gleam/int
import gleam_community/colour
import lustre/attribute
import lustre/element.{type Element}
import lustre/element/svg

pub fn draw(count: Int) -> List(#(String, Element(GameMsg))) {
  let countdown_colour = case colour.from_hsla(1.0, 1.0, 0.0, 0.15) {
    Ok(c) -> c
    Error(_) -> colour.black
  }

  let countdown_text =
    svg.text(
      [
        attribute.attribute("x", "50%"),
        attribute.attribute("y", "50%"),
        attribute.attribute("text-anchor", "middle"),
        attribute.attribute("dominant-baseline", "middle"),
        attribute.attribute("font-size", "200"),
        attribute.attribute("font-family", "sans-serif"),
        attribute.attribute("fill", colour.to_css_rgba_string(countdown_colour)),
      ],
      int.to_string(count),
    )
  [#("countdown", countdown_text)]
}
