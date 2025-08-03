import gleam/float
import gleam/int
import gleam_community/colour

@external(erlang, "erlang", "phash2")
fn phash2(uuid: String) -> Int

pub fn colour_for_uuid(uuid: String) -> colour.Colour {
  let hash = phash2(uuid)
  let hue = int.absolute_value(hash)
  let assert Ok(hue) = float.modulo(int.to_float(hue), 256.0)
  let assert Ok(colour) = colour.from_hsl(hue /. 256.0, 0.5, 0.9)
  colour
}
