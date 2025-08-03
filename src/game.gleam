import constants.{height, tick_delay_ms, width}
import countdown
import game_message.{type Msg}
import gleam/dict
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

pub fn component() -> App(Nil, Model, Msg) {
  lustre.application(init, update, view)
}

pub type Model {
  Model(
    game_state: GameState,
    players: dict.Dict(Int, player.Player),
    timer: Option(game_message.TimerID),
    countdown_timer: Option(game_message.TimerID),
  )
}

pub type GameState {
  NotStarted
  Countdown(Int)
  Playing
  Ended
}

fn init(_) -> #(Model, Effect(Msg)) {
  let model =
    Model(
      game_state: NotStarted,
      players: dict.new(),
      timer: None,
      countdown_timer: None,
    )

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

fn countdown_effect() -> Effect(Msg) {
  effect.from(fn(dispatch) {
    case
      game_message.apply_interval(1000, fn() {
        dispatch(game_message.CountdownTick)
      })
    {
      Ok(timer) -> dispatch(game_message.NewCountdownTimer(timer))
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

fn handle_turn(
  players: dict.Dict(Int, player.Player),
  player_id: Int,
  direction: player.TurnDirection,
) -> dict.Dict(Int, player.Player) {
  case dict.get(players, player_id) {
    Ok(p) -> dict.insert(players, player_id, player.turn(p, direction))
    Error(_) -> players
  }
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    game_message.NewTimer(timer) -> #(
      Model(..model, timer: Some(timer)),
      effect.none(),
    )

    game_message.NewCountdownTimer(timer) -> #(
      Model(..model, countdown_timer: Some(timer)),
      effect.none(),
    )

    game_message.CountdownTick -> {
      let players_with_speed =
        dict.map_values(model.players, fn(_, p) {
          p |> player.update_speed(1.0)
        })

      case model.game_state {
        Countdown(count) ->
          case count {
            1 -> #(
              Model(..model, game_state: Playing, players: players_with_speed),
              cancel_timer(model.countdown_timer),
            )
            _ -> #(
              Model(..model, game_state: Countdown(count - 1)),
              effect.none(),
            )
          }
        _ -> #(model, effect.none())
      }
    }

    game_message.StartGame -> {
      let p =
        player.Player(
          id: 1,
          x: 250.0,
          y: 250.0,
          speed: 0.0,
          angle: 0.0,
          tail: [],
          turning: player.Straight,
        )
      #(
        Model(
          game_state: Countdown(3),
          players: dict.from_list([#(p.id, p)]),
          // Will be set by the NewTimer message
          timer: None,
          countdown_timer: None,
        ),
        effect.batch([countdown_effect(), tick_effect()]),
      )
    }

    game_message.Tick -> {
      let new_players =
        dict.map_values(model.players, fn(_, p) { player.update(p) })
      let collided_players =
        new_players
        |> dict.values
        |> list.filter(player.check_collision)

      case collided_players {
        [] -> #(Model(..model, players: new_players), effect.none())
        _ -> #(Model(..model, game_state: Ended), cancel_timer(model.timer))
      }
    }

    game_message.KeyDown(player_id, "ArrowLeft") -> {
      #(
        Model(
          ..model,
          players: handle_turn(model.players, player_id, player.Left),
        ),
        effect.none(),
      )
    }

    game_message.KeyDown(player_id, "ArrowRight") -> {
      #(
        Model(
          ..model,
          players: handle_turn(model.players, player_id, player.Right),
        ),
        effect.none(),
      )
    }

    game_message.KeyDown(_, _) -> #(model, effect.none())

    game_message.KeyUp(player_id, "ArrowLeft")
    | game_message.KeyUp(player_id, "ArrowRight") -> {
      #(
        Model(
          ..model,
          players: handle_turn(model.players, player_id, player.Straight),
        ),
        effect.none(),
      )
    }

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

  let player_elements = list.flat_map(dict.values(model.players), player.draw)

  let overlay_elements = case model.game_state {
    NotStarted -> {
      [overlay_text("Click to Start")]
    }
    Countdown(count) -> {
      countdown.draw(count)
    }
    Playing -> []
    Ended -> {
      [overlay_text("Game Over")]
    }
  }

  let svg_children = case model.game_state {
    NotStarted | Ended -> overlay_elements
    Countdown(_) -> list.flatten([overlay_elements, player_elements])
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

fn overlay_text(text: String) -> #(String, Element(Msg)) {
  let text_element =
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
      text,
    )
  #("overlay", text_element)
}
