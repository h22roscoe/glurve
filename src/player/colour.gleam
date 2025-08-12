import gleam/float
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

pub fn to_svg_head(
  colour: Colour,
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

  let href =
    "/static/curve-fever-heads-and-tails/triangle_"
    <> colour_slug(colour)
    <> ".svg"

  svg.image([
    attribute.attribute("href", href),
    attribute.attribute("width", "100"),
    attribute.attribute("height", "100"),
    attribute.attribute("transform", matrix),
  ])
}

pub fn to_svg_tail(
  colour: Colour,
  x: Float,
  y: Float,
  tail_radius: Float,
) -> element.Element(a) {
  // Asset circle has center (50,50) and r=30 in a 100x100 viewBox.
  // Scale so r maps to tail_radius, then translate so center maps to (x,y).
  let s = tail_radius /. 30.0
  let tx = x -. s *. 50.0
  let ty = y -. s *. 50.0
  let matrix =
    "matrix("
    <> float.to_string(s)
    <> " 0 0 "
    <> float.to_string(s)
    <> " "
    <> float.to_string(tx)
    <> " "
    <> float.to_string(ty)
    <> ")"

  let href =
    "/static/curve-fever-heads-and-tails/circle_"
    <> colour_slug(colour)
    <> ".svg"

  svg.image([
    attribute.attribute("href", href),
    attribute.attribute("width", "100"),
    attribute.attribute("height", "100"),
    attribute.attribute("transform", matrix),
  ])
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
