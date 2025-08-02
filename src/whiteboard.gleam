import gleam/float
import gleam/int
import gleam/list
import gleam_community/maths
import lustre.{type App}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/keyed
import lustre/element/svg
import lustre/event
import lustre/server_component

const speed = 1.0

const turn_rate = 0.05

const width = 500

const height = 500

// ---
// MAIN
// ---
pub fn component() -> App(Nil, Model, Msg) {
  lustre.application(init, update, view)
}

// ---
// MODEL
// ---
pub type Model {
  Model(
    x: Float,
    y: Float,
    angle: Float,
    tail: List(#(Float, Float)),
    turning: TurnDirection,
  )
}

pub type TurnDirection {
  Left
  Right
  Straight
}

type TimerID

@external(erlang, "timer", "apply_interval")
fn apply_interval(
  delay_ms: Int,
  callback: fn() -> any,
) -> Result(TimerID, String)

fn init(_) -> #(Model, Effect(Msg)) {
  let model = Model(x: 250.0, y: 250.0, angle: 0.0, tail: [], turning: Straight)
  let tick_effect =
    effect.from(fn(dispatch) {
      case apply_interval(10, fn() { dispatch(Tick) }) {
        Ok(_) -> Nil
        Error(_) -> {
          // In a real app, you'd want to log this error!
          Nil
        }
      }
    })
  #(model, tick_effect)
}

// ---
// UPDATE
// ---
pub type Msg {
  Tick
  KeyDown(String)
  KeyUp(String)
  NoOp
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  let new_model = case msg {
    Tick -> {
      let angle = case model.turning {
        Left -> model.angle -. turn_rate
        Right -> model.angle +. turn_rate
        Straight -> model.angle
      }

      let new_x = model.x +. maths.cos(angle) *. speed
      let new_y = model.y +. maths.sin(angle) *. speed

      let wrapped_x = case new_x >. int.to_float(width) {
        True -> 0.0
        False ->
          case new_x <. 0.0 {
            True -> int.to_float(width)
            False -> new_x
          }
      }

      let wrapped_y = case new_y >. int.to_float(height) {
        True -> 0.0
        False ->
          case new_y <. 0.0 {
            True -> int.to_float(height)
            False -> new_y
          }
      }

      let new_tail = [#(wrapped_x, wrapped_y), ..model.tail]
      Model(..model, x: wrapped_x, y: wrapped_y, angle: angle, tail: new_tail)
    }

    KeyDown("ArrowLeft") -> Model(..model, turning: Left)
    KeyDown("ArrowRight") -> Model(..model, turning: Right)
    KeyDown(_) -> model

    KeyUp("ArrowLeft") | KeyUp("ArrowRight") ->
      Model(..model, turning: Straight)
    KeyUp(_) -> model

    NoOp -> model
  }

  #(new_model, effect.none())
}

// ---
// VIEW
// ---
fn view(model: Model) -> Element(Msg) {
  let on_key_down =
    event.on_keydown(fn(key) {
      case key {
        "ArrowLeft" | "A" | "a" -> KeyDown("ArrowLeft")
        "ArrowRight" | "D" | "d" -> KeyDown("ArrowRight")
        _ -> NoOp
      }
    })

  let on_key_up =
    event.on_keyup(fn(key) {
      case key {
        "ArrowLeft" | "A" | "a" -> KeyUp("ArrowLeft")
        "ArrowRight" | "D" | "d" -> KeyUp("ArrowRight")
        _ -> NoOp
      }
    })

  let tail_points =
    model.tail
    |> list.map(fn(pos) {
      let #(x, y) = pos
      svg.circle([
        attribute.attribute("cx", float.to_string(x)),
        attribute.attribute("cy", float.to_string(y)),
        attribute.attribute("r", "3"),
        attribute.attribute("fill", "black"),
      ])
    })

  let head =
    svg.circle([
      attribute.attribute("cx", float.to_string(model.x)),
      attribute.attribute("cy", float.to_string(model.y)),
      attribute.attribute("r", "5"),
      attribute.attribute("fill", "black"),
    ])

  let head_keyed = #("head", head)

  let tail_points_len = list.length(tail_points)
  let tail_points_keyed =
    tail_points
    |> list.index_map(fn(pos, index) {
      #("tail-" <> int.to_string(tail_points_len - index - 1), pos)
    })

  element.fragment([html.style([], { "
      svg {
        background-color: oklch(98.4% 0.003 247.858);
        top: 5;
        left: 5;
        width: " <> int.to_string(width) <> "px;
        height: " <> int.to_string(height) <> "px;
      }
      " }), keyed.namespaced(
      "http://www.w3.org/2000/svg",
      "svg",
      [
        attribute.tabindex(0),
        server_component.include(on_key_down, ["key"]),
        server_component.include(on_key_up, ["key"]),
      ],
      [head_keyed, ..tail_points_keyed],
    )])
}
