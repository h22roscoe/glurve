import game_message.{type Msg}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import lustre.{type App}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/keyed
import lustre/element/svg
import lustre/event
import lustre/server_component
import player

const tick_delay_ms = 10

const width = 500

const height = 500

pub fn component() -> App(Nil, Model, Msg) {
  lustre.application(init, update, view)
}

pub type Model {
  Model(
    game_state: GameState,
    players: List(player.Player),
    timer: Option(game_message.TimerID),
  )
}

pub type GameState {
  NotStarted
  Playing
  Ended
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model = Model(game_state: NotStarted, players: [], timer: None)

  #(model, effect.none())
}

fn tick_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    case
      game_message.apply_interval(tick_delay_ms, fn() {
        dispatch(game_message.Tick)
      })
    {
      Ok(timer) -> dispatch(game_message.NewTimer(timer))
      Error(_) -> Nil
    }
  })
}

fn cancel_timer(timer: Option(game_message.TimerID)) -> Effect(Msg) {
  case timer {
    Some(timer) ->
      effect.from(fn(dispatch) {
        let _ = game_message.cancel(timer)
        dispatch(game_message.NoOp)
      })
    None -> effect.none()
  }
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    game_message.NewTimer(timer) -> #(
      Model(..model, timer: Some(timer)),
      effect.none(),
    )

    game_message.StartGame -> {
      let player =
        player.Player(
          id: 1,
          x: 250.0,
          y: 250.0,
          angle: 0.0,
          tail: [],
          turning: player.Straight,
        )
      #(
        Model(
          game_state: Playing,
          players: [player],
          // Will be set by the NewTimer message
          timer: None,
        ),
        tick_effect(),
      )
    }

    game_message.Tick -> {
      let new_players = list.map(model.players, player.update)
      let collided_players = list.filter(new_players, player.check_collision)

      case collided_players {
        [] -> #(Model(..model, players: new_players), effect.none())
        _ -> #(Model(..model, game_state: Ended), cancel_timer(model.timer))
      }
    }

    game_message.KeyDown(player_id, "ArrowLeft") -> #(
      Model(
        ..model,
        players: list.map(model.players, fn(p) {
          case p.id == player_id {
            True -> player.turn(p, player.Left)
            False -> p
          }
        }),
      ),
      effect.none(),
    )

    game_message.KeyDown(player_id, "ArrowRight") -> #(
      Model(
        ..model,
        players: list.map(model.players, fn(p) {
          case p.id == player_id {
            True -> player.turn(p, player.Right)
            False -> p
          }
        }),
      ),
      effect.none(),
    )

    game_message.KeyDown(_, _) -> #(model, effect.none())

    game_message.KeyUp(player_id, "ArrowLeft")
    | game_message.KeyUp(player_id, "ArrowRight") -> #(
      Model(
        ..model,
        players: list.map(model.players, fn(p) {
          case p.id == player_id {
            True -> player.turn(p, player.Straight)
            False -> p
          }
        }),
      ),
      effect.none(),
    )

    game_message.KeyUp(_, _) -> #(model, effect.none())

    game_message.NoOp -> #(model, effect.none())
  }
}

fn view(model: Model) -> Element(Msg) {
  let on_key_down =
    event.on_keydown(fn(key) {
      case key {
        "ArrowLeft" | "A" | "a" -> game_message.KeyDown(1, "ArrowLeft")
        "ArrowRight" | "D" | "d" -> game_message.KeyDown(1, "ArrowRight")
        _ -> game_message.NoOp
      }
    })

  let on_key_up =
    event.on_keyup(fn(key) {
      case key {
        "ArrowLeft" | "A" | "a" -> game_message.KeyUp(1, "ArrowLeft")
        "ArrowRight" | "D" | "d" -> game_message.KeyUp(1, "ArrowRight")
        _ -> game_message.NoOp
      }
    })

  let player_elements = list.flat_map(model.players, player.draw)

  let overlay_elements = case model.game_state {
    NotStarted -> {
      let start_button =
        svg.text(
          [
            attribute.attribute("x", "50%"),
            attribute.attribute("y", "50%"),
            attribute.attribute("text-anchor", "middle"),
            attribute.attribute("dominant-baseline", "middle"),
            attribute.attribute("font-size", "24"),
            attribute.attribute("font-family", "sans-serif"),
            attribute.attribute("fill", "black"),
            attribute.style("cursor", "pointer"),
            event.on_click(game_message.StartGame),
          ],
          "Click to Start",
        )
      [#("start", start_button)]
    }
    Playing -> []
    Ended -> {
      let end_text =
        svg.text(
          [
            attribute.attribute("x", "50%"),
            attribute.attribute("y", "50%"),
            attribute.attribute("text-anchor", "middle"),
            attribute.attribute("dominant-baseline", "middle"),
            attribute.attribute("font-size", "24"),
            attribute.attribute("font-family", "sans-serif"),
            attribute.attribute("fill", "black"),
            attribute.style("cursor", "pointer"),
            event.on_click(game_message.StartGame),
          ],
          "Game Over",
        )
      [#("end", end_text)]
    }
  }

  let svg_children = case model.game_state {
    NotStarted | Ended -> overlay_elements
    _ -> player_elements
  }

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
        attribute.attribute("width", int.to_string(width)),
        attribute.attribute("height", int.to_string(height)),
        attribute.tabindex(0),
        server_component.include(on_key_down, ["key"]),
        server_component.include(on_key_up, ["key"]),
      ],
      svg_children,
    )])
}
