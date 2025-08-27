import gleam/set
import lustre/attribute
import lustre/element
import lustre/element/svg

pub type Colour {
  Bee
  Blue
  Camo
  Circuit
  Cyan
  Eye
  Galaxy
  Green
  Ice
  Lightning
  Lime
  Magenta
  Melon
  Orange
  Pink
  Pirate
  Purple
  Rainbow
  Red
  Shark
  Slate
  Spots
  Teal
  Yellow
}

pub fn all() -> set.Set(Colour) {
  set.from_list([
    Bee,
    Blue,
    Camo,
    Circuit,
    Cyan,
    Eye,
    Galaxy,
    Green,
    Ice,
    Lightning,
    Lime,
    Magenta,
    Melon,
    Orange,
    Pink,
    Pirate,
    Purple,
    Rainbow,
    Red,
    Shark,
    Slate,
    Spots,
    Teal,
    Yellow,
  ])
}

pub fn to_string(colour: Colour) -> String {
  case colour {
    Bee -> "Bee"
    Blue -> "Blue"
    Camo -> "Camo"
    Circuit -> "Circuit"
    Cyan -> "Cyan"
    Eye -> "Eye"
    Galaxy -> "Galaxy"
    Green -> "Green"
    Ice -> "Ice"
    Lightning -> "Lightning"
    Lime -> "Lime"
    Magenta -> "Magenta"
    Melon -> "Melon"
    Orange -> "Orange"
    Pink -> "Pink"
    Pirate -> "Pirate"
    Purple -> "Purple"
    Rainbow -> "Rainbow"
    Red -> "Red"
    Shark -> "Shark"
    Slate -> "Slate"
    Spots -> "Spots"
    Teal -> "Teal"
    Yellow -> "Yellow"
  }
}

pub fn to_tail_styles(colour: Colour) -> attribute.Attribute(a) {
  attribute.class("trail trail--" <> colour_slug(colour))
}

pub fn to_svg_head_href(colour: Colour) -> String {
  "/static/curve-fever-heads-and-tails/triangle_"
  <> colour_slug(colour)
  <> ".svg"
}

pub fn svg_defs() -> List(#(String, element.Element(a))) {
  [
    #(
      "defs",
      svg.defs([], [
        // Rainbow
        svg.linear_gradient(
          [
            attribute.id("grad-rainbow"),
            attribute.attribute("x1", "0%"),
            attribute.attribute("y1", "0%"),
            attribute.attribute("x2", "100%"),
            attribute.attribute("y2", "0%"),
            attribute.attribute("gradientUnits", "userSpaceOnUse"),
          ],
          [
            svg.stop([
              attribute.attribute("offset", "0%"),
              attribute.attribute("stop-color", "#FF3B30"),
            ]),
            svg.stop([
              attribute.attribute("offset", "16%"),
              attribute.attribute("stop-color", "#FF9500"),
            ]),
            svg.stop([
              attribute.attribute("offset", "33%"),
              attribute.attribute("stop-color", "#FFD400"),
            ]),
            svg.stop([
              attribute.attribute("offset", "50%"),
              attribute.attribute("stop-color", "#34C759"),
            ]),
            svg.stop([
              attribute.attribute("offset", "66%"),
              attribute.attribute("stop-color", "#00C7BE"),
            ]),
            svg.stop([
              attribute.attribute("offset", "83%"),
              attribute.attribute("stop-color", "#007AFF"),
            ]),
            svg.stop([
              attribute.attribute("offset", "100%"),
              attribute.attribute("stop-color", "#AF52DE"),
            ]),
          ],
        ),
        // Camo
        svg.linear_gradient(
          [
            attribute.id("grad-camo"),
            attribute.attribute("x1", "0%"),
            attribute.attribute("y1", "0%"),
            attribute.attribute("x2", "100%"),
            attribute.attribute("y2", "0%"),
            attribute.attribute("gradientUnits", "userSpaceOnUse"),
          ],
          [
            svg.stop([
              attribute.attribute("offset", "0%"),
              attribute.attribute("stop-color", "#3B5323"),
            ]),
            svg.stop([
              attribute.attribute("offset", "35%"),
              attribute.attribute("stop-color", "#556B2F"),
            ]),
            svg.stop([
              attribute.attribute("offset", "70%"),
              attribute.attribute("stop-color", "#6B8E23"),
            ]),
            svg.stop([
              attribute.attribute("offset", "100%"),
              attribute.attribute("stop-color", "#3B5323"),
            ]),
          ],
        ),
        // Galaxy
        svg.linear_gradient(
          [
            attribute.id("grad-galaxy"),
            attribute.attribute("x1", "0%"),
            attribute.attribute("y1", "0%"),
            attribute.attribute("x2", "100%"),
            attribute.attribute("y2", "0%"),
            attribute.attribute("gradientUnits", "userSpaceOnUse"),
          ],
          [
            svg.stop([
              attribute.attribute("offset", "0%"),
              attribute.attribute("stop-color", "#5A00FF"),
            ]),
            svg.stop([
              attribute.attribute("offset", "50%"),
              attribute.attribute("stop-color", "#7A30FF"),
            ]),
            svg.stop([
              attribute.attribute("offset", "100%"),
              attribute.attribute("stop-color", "#00D1FF"),
            ]),
          ],
        ),
        // Melon (green -> white -> pink)
        svg.linear_gradient(
          [
            attribute.id("grad-melon"),
            attribute.attribute("x1", "50%"),
            attribute.attribute("y1", "0%"),
            attribute.attribute("x2", "50%"),
            attribute.attribute("y2", "100%"),
            attribute.attribute("gradientUnits", "userSpaceOnUse"),
          ],
          [
            svg.stop([
              attribute.attribute("offset", "0%"),
              attribute.attribute("stop-color", "#2ECC71"),
            ]),
            svg.stop([
              attribute.attribute("offset", "35%"),
              attribute.attribute("stop-color", "#9EF0B3"),
            ]),
            svg.stop([
              attribute.attribute("offset", "50%"),
              attribute.attribute("stop-color", "#FFFFFF"),
            ]),
            svg.stop([
              attribute.attribute("offset", "65%"),
              attribute.attribute("stop-color", "#FFD1DC"),
            ]),
            svg.stop([
              attribute.attribute("offset", "100%"),
              attribute.attribute("stop-color", "#FF6B6B"),
            ]),
          ],
        ),
        // Eye
        svg.linear_gradient(
          [
            attribute.id("grad-eye"),
            attribute.attribute("x1", "0%"),
            attribute.attribute("y1", "0%"),
            attribute.attribute("x2", "100%"),
            attribute.attribute("y2", "100%"),
            attribute.attribute("gradientUnits", "userSpaceOnUse"),
          ],
          [
            svg.stop([
              attribute.attribute("offset", "0%"),
              attribute.attribute("stop-color", "#FFFFFF"),
            ]),
            svg.stop([
              attribute.attribute("offset", "30%"),
              attribute.attribute("stop-color", "#2035aaff"),
            ]),
            svg.stop([
              attribute.attribute("offset", "100%"),
              attribute.attribute("stop-color", "#0cd3e1ff"),
            ]),
          ],
        ),
        // Glow galaxy
        svg.filter(
          [
            attribute.id("glow-galaxy"),
            attribute.attribute("x", "-50%"),
            attribute.attribute("y", "-50%"),
            attribute.attribute("width", "200%"),
            attribute.attribute("height", "200%"),
          ],
          [
            svg.fe_gaussian_blur([
              attribute.attribute("stdDeviation", "2.5"),
              attribute.attribute("result", "blur"),
            ]),
            svg.fe_merge([], [
              svg.fe_merge_node([attribute.attribute("in", "blur")]),
              svg.fe_merge_node([attribute.attribute("in", "SourceGraphic")]),
            ]),
          ],
        ),
        // Glow lightning
        svg.filter(
          [
            attribute.id("glow-lightning"),
            attribute.attribute("x", "-60%"),
            attribute.attribute("y", "-60%"),
            attribute.attribute("width", "220%"),
            attribute.attribute("height", "220%"),
          ],
          [
            svg.fe_gaussian_blur([
              attribute.attribute("stdDeviation", "4"),
              attribute.attribute("result", "blur"),
            ]),
            svg.fe_merge([], [
              svg.fe_merge_node([attribute.attribute("in", "blur")]),
              svg.fe_merge_node([attribute.attribute("in", "SourceGraphic")]),
            ]),
          ],
        ),
        // Glow circuit
        svg.filter(
          [
            attribute.id("glow-circuit"),
            attribute.attribute("x", "-50%"),
            attribute.attribute("y", "-50%"),
            attribute.attribute("width", "200%"),
            attribute.attribute("height", "200%"),
          ],
          [
            svg.fe_gaussian_blur([
              attribute.attribute("stdDeviation", "2"),
              attribute.attribute("result", "blur"),
            ]),
            svg.fe_merge([], [
              svg.fe_merge_node([attribute.attribute("in", "blur")]),
              svg.fe_merge_node([attribute.attribute("in", "SourceGraphic")]),
            ]),
          ],
        ),
        // Glow eye
        svg.filter(
          [
            attribute.id("glow-eye"),
            attribute.attribute("x", "-50%"),
            attribute.attribute("y", "-50%"),
            attribute.attribute("width", "200%"),
            attribute.attribute("height", "200%"),
          ],
          [
            svg.fe_gaussian_blur([
              attribute.attribute("stdDeviation", "3"),
              attribute.attribute("result", "blur"),
            ]),
            svg.fe_merge([], [
              svg.fe_merge_node([attribute.attribute("in", "blur")]),
              svg.fe_merge_node([attribute.attribute("in", "SourceGraphic")]),
            ]),
          ],
        ),
        // Glow ice
        svg.filter(
          [
            attribute.id("glow-ice"),
            attribute.attribute("x", "-50%"),
            attribute.attribute("y", "-50%"),
            attribute.attribute("width", "200%"),
            attribute.attribute("height", "200%"),
          ],
          [
            svg.fe_gaussian_blur([
              attribute.attribute("stdDeviation", "1.4"),
              attribute.attribute("result", "blur"),
            ]),
            svg.fe_merge([], [
              svg.fe_merge_node([attribute.attribute("in", "blur")]),
              svg.fe_merge_node([attribute.attribute("in", "SourceGraphic")]),
            ]),
          ],
        ),
      ]),
    ),
  ]
}

fn colour_slug(colour: Colour) -> String {
  case colour {
    Bee -> "bee"
    Blue -> "blue"
    Camo -> "camo"
    Circuit -> "circuit"
    Cyan -> "cyan"
    Eye -> "eye"
    Galaxy -> "galaxy"
    Green -> "green"
    Ice -> "ice"
    Lightning -> "lightning"
    Lime -> "lime"
    Magenta -> "magenta"
    Melon -> "melon"
    Orange -> "orange"
    Pink -> "pink"
    Pirate -> "pirate"
    Purple -> "purple"
    Rainbow -> "rainbow"
    Red -> "red"
    Shark -> "shark"
    Slate -> "slate"
    Spots -> "spots"
    Teal -> "teal"
    Yellow -> "yellow"
  }
}
