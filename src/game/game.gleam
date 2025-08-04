import game/countdown
import game/game_message.{type GameMsg}
import gleam/dict
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/yielder
import glubsub
import lustre.{type App}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/keyed
import lustre/element/svg
import lustre/event
import lustre/server_component
import player/draw
import player/player
import position
import uuid_colour

const height = 500

const width = 500

const tick_delay_ms = 10

pub type StartArgs {
  StartArgs(id: String, topic: glubsub.Topic(game_message.SharedMsg))
}

pub fn component() -> App(StartArgs, Model, GameMsg) {
  lustre.application(init, update, view)
}

pub type Model {
  Model(
    topic: glubsub.Topic(game_message.SharedMsg),
    game_state: GameState,
    player_id: String,
    players: dict.Dict(String, player.Player),
    timer: Option(game_message.TimerID),
    countdown_timer: Option(game_message.TimerID),
  )
}

pub type GameState {
  NotStarted
  Countdown(Int)
  Playing
  Crashed
  Ended
}

fn subscribe(
  topic: glubsub.Topic(topic),
  on_msg handle_msg: fn(topic) -> msg,
) -> Effect(msg) {
  // Using the special `select` effect, we get a fresh new subject that we can
  // use to subscribe to glubsub.
  use _dispatch, subject <- server_component.select

  let assert Ok(_) = glubsub.subscribe(topic, subject)

  // We need to teach the server component runtime to listen for messages on
  // this subject by returning a `Selector` that matches our apps `msg` type.
  let selector =
    process.new_selector()
    |> process.select_map(subject, handle_msg)

  selector
}

fn init(start_args: StartArgs) -> #(Model, Effect(GameMsg)) {
  let this_player =
    player.Player(
      id: start_args.id,
      position: position.random_start_position(height, width)
        |> yielder.first()
        |> result.unwrap(position.Position(x: 0.0, y: 0.0)),
      speed: 0.0,
      angle: 0.0,
      colour: uuid_colour.colour_for_uuid(start_args.id),
      tail: [],
      turning: player.Straight,
    )
  let model =
    Model(
      topic: start_args.topic,
      game_state: NotStarted,
      player_id: start_args.id,
      players: dict.from_list([#(start_args.id, this_player)]),
      timer: None,
      countdown_timer: None,
    )

  #(
    model,
    effect.batch([
      subscribe(start_args.topic, game_message.RecievedSharedMsg),
      broadcast(start_args.topic, game_message.PlayerJoined(start_args.id)),
    ]),
  )
}

fn tick_effect() -> Effect(GameMsg) {
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

fn countdown_effect() -> Effect(GameMsg) {
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

fn cancel_timer(timer: Option(game_message.TimerID)) -> Effect(GameMsg) {
  case timer {
    Some(timer) ->
      effect.from(fn(dispatch) {
        let _ = game_message.cancel(timer)
        dispatch(game_message.NoOp)
      })
    None -> effect.none()
  }
}

fn broadcast(channel: glubsub.Topic(msg), msg: msg) -> Effect(any) {
  use _dispatch <- effect.from
  let assert Ok(_) = glubsub.broadcast(channel, msg)
  Nil
}

fn handle_turn(
  players: dict.Dict(String, player.Player),
  player_id: String,
  direction: player.TurnDirection,
) -> dict.Dict(String, player.Player) {
  case dict.get(players, player_id) {
    Ok(p) -> dict.insert(players, player_id, player.turn(p, direction))
    Error(_) -> players
  }
}

fn handle_shared_msg(
  model: Model,
  shared_msg: game_message.SharedMsg,
) -> #(Model, Effect(GameMsg)) {
  case shared_msg {
    game_message.PlayerJoined(player_id) -> #(
      Model(
        ..model,
        players: dict.insert(
          model.players,
          player_id,
          player.Player(
            id: player_id,
            colour: uuid_colour.colour_for_uuid(player_id),
            position: position.Position(x: 0.0, y: 0.0),
            speed: 0.0,
            angle: 0.0,
            tail: [],
            turning: player.Straight,
          ),
        ),
      ),
      broadcast(model.topic, game_message.ExistingPlayer(model.player_id)),
    )
    game_message.ExistingPlayer(player_id) -> #(
      Model(
        ..model,
        players: dict.insert(
          model.players,
          player_id,
          player.Player(
            id: player_id,
            colour: uuid_colour.colour_for_uuid(player_id),
            position: position.Position(x: 0.0, y: 0.0),
            speed: 0.0,
            angle: 0.0,
            tail: [],
            turning: player.Straight,
          ),
        ),
      ),
      effect.none(),
    )
    game_message.PlayerCrashed(player_id) -> {
      let assert Ok(that_player) = dict.get(model.players, player_id)
      let that_player_crashed = player.Player(..that_player, speed: 0.0)
      let new_players =
        dict.insert(model.players, player_id, that_player_crashed)
      let uncrashed_players =
        dict.fold(new_players, 0, fn(acc, _, p) {
          case p.speed == 0.0 {
            True -> acc
            False -> acc + 1
          }
        })
      let finished = uncrashed_players <= 1
      case finished {
        True -> #(
          Model(..model, players: new_players, game_state: Ended),
          cancel_timer(model.timer),
        )
        False -> #(Model(..model, players: new_players), effect.none())
      }
    }
    game_message.StartedGame -> {
      let num_players = dict.size(model.players)
      let positions =
        yielder.take(position.random_start_position(height, width), num_players)
        |> yielder.to_list()
      let players =
        dict.to_list(model.players)
        |> list.zip(positions)
        |> list.map(fn(zipped) {
          let #(#(id, player), pos) = zipped
          #(id, player.Player(..player, position: pos))
        })
        |> dict.from_list()
      #(
        Model(
          ..model,
          players: players,
          game_state: Countdown(3),
          // Will be set by the NewTimer message
          timer: None,
          countdown_timer: None,
        ),
        effect.batch([countdown_effect(), tick_effect()]),
      )
    }
    game_message.PlayerTurning(player_id, direction) -> {
      case player_id == model.player_id {
        True -> #(model, effect.none())
        False -> #(
          Model(
            ..model,
            players: handle_turn(model.players, player_id, direction),
          ),
          effect.none(),
        )
      }
    }
  }
}

fn update(model: Model, msg: GameMsg) -> #(Model, Effect(GameMsg)) {
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

    game_message.KickOffGame -> #(
      model,
      broadcast(model.topic, game_message.StartedGame),
    )

    game_message.RecievedSharedMsg(shared_msg) ->
      handle_shared_msg(model, shared_msg)

    game_message.Tick -> {
      let new_players =
        dict.map_values(model.players, fn(_, p) {
          player.update(p, height, width)
        })
      let assert Ok(this_player) = dict.get(new_players, model.player_id)
      let player_collided_with_self =
        player.check_collision_with_self(this_player)
      let player_collided_with_edges =
        player.check_collision_with_edges(this_player, height, width)
      let players_collided_with_other_players =
        player.check_collision_with_other_players(this_player, new_players)
      let player_collided =
        player_collided_with_self
        || player_collided_with_edges
        || players_collided_with_other_players

      let new_players_with_crashed =
        dict.insert(
          new_players,
          model.player_id,
          player.Player(..this_player, speed: 0.0),
        )

      case player_collided {
        False -> #(Model(..model, players: new_players), effect.none())
        _ -> #(
          Model(..model, players: new_players_with_crashed, game_state: Crashed),
          broadcast(model.topic, game_message.PlayerCrashed(model.player_id)),
        )
      }
    }

    game_message.KeyDown("ArrowRight") -> {
      let broadcast_msg =
        game_message.PlayerTurning(model.player_id, player.Right)
      let broadcast_effect = broadcast(model.topic, broadcast_msg)

      #(
        Model(
          ..model,
          players: handle_turn(model.players, model.player_id, player.Right),
        ),
        broadcast_effect,
      )
    }

    game_message.KeyDown("ArrowLeft") -> {
      let broadcast_msg =
        game_message.PlayerTurning(model.player_id, player.Left)
      let broadcast_effect = broadcast(model.topic, broadcast_msg)
      #(
        Model(
          ..model,
          players: handle_turn(model.players, model.player_id, player.Left),
        ),
        broadcast_effect,
      )
    }

    game_message.KeyDown(_) -> #(model, effect.none())

    game_message.KeyUp("ArrowLeft") | game_message.KeyUp("ArrowRight") -> {
      let broadcast_msg =
        game_message.PlayerTurning(model.player_id, player.Straight)
      let broadcast_effect = broadcast(model.topic, broadcast_msg)
      #(
        Model(
          ..model,
          players: handle_turn(model.players, model.player_id, player.Straight),
        ),
        broadcast_effect,
      )
    }

    game_message.KeyUp(_) -> #(model, effect.none())

    game_message.ReturnToLobby -> {
      echo "ReturnToLobby"
      #(model, server_component.emit("navigate", json.string("/")))
    }

    game_message.NoOp -> #(model, effect.none())
  }
}

fn view(model: Model) -> Element(GameMsg) {
  let on_key_down =
    event.on_keydown(fn(key) {
      case key {
        "ArrowLeft" | "A" | "a" -> game_message.KeyDown("ArrowLeft")
        "ArrowRight" | "D" | "d" -> game_message.KeyDown("ArrowRight")
        _ -> game_message.NoOp
      }
    })

  let on_key_up =
    event.on_keyup(fn(key) {
      case key {
        "ArrowLeft" | "A" | "a" -> game_message.KeyUp("ArrowLeft")
        "ArrowRight" | "D" | "d" -> game_message.KeyUp("ArrowRight")
        _ -> game_message.NoOp
      }
    })

  let player_elements =
    list.flat_map(dict.values(model.players), draw.draw_player)
  let num_players = dict.size(model.players)
  let players_list =
    dict.values(model.players)
    |> list.map(fn(p: player.Player) { p.id })
    |> list.index_map(fn(id, idx) {
      overlay_text_with_index("Player: " <> id, idx, num_players)
    })

  let start_text_element =
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
        event.on_click(game_message.KickOffGame),
      ],
      "Click to Start",
    )

  let game_over_text_element =
    svg.text(
      [
        attribute.attribute("x", "50%"),
        attribute.attribute("y", "45%"),
        attribute.attribute("text-anchor", "middle"),
        attribute.attribute("dominant-baseline", "middle"),
        attribute.attribute("font-size", "24"),
        attribute.attribute("font-family", "sans-serif"),
        attribute.attribute("fill", "black"),
      ],
      "Game Over",
    )

  let winner_text_element =
    svg.text(
      [
        attribute.attribute("x", "50%"),
        attribute.attribute("y", "45%"),
        attribute.attribute("text-anchor", "middle"),
        attribute.attribute("dominant-baseline", "middle"),
        attribute.attribute("font-size", "24"),
        attribute.attribute("font-family", "sans-serif"),
        attribute.attribute("fill", "black"),
      ],
      "You Win!",
    )

  let click_to_return_text_element =
    svg.text(
      [
        attribute.attribute("x", "50%"),
        attribute.attribute("y", "60%"),
        attribute.attribute("text-anchor", "middle"),
        attribute.attribute("dominant-baseline", "middle"),
        attribute.attribute("font-size", "14"),
        attribute.attribute("font-family", "sans-serif"),
        attribute.attribute("fill", "gray"),
        event.on_click(game_message.ReturnToLobby),
      ],
      "Click anywhere to return to lobby",
    )

  let overlay_elements = case model.game_state {
    NotStarted -> {
      [#("start", start_text_element), ..players_list]
    }
    Countdown(count) -> {
      countdown.draw(count)
    }
    Ended -> {
      let winner =
        model.players
        |> dict.values
        |> list.filter(fn(p) { p.speed != 0.0 })
        |> list.first()
      case winner {
        Ok(winner) -> {
          case winner.id == model.player_id {
            True -> [
              #("winner", winner_text_element),
              #("click_to_return", click_to_return_text_element),
            ]
            False -> [
              #("game_over", game_over_text_element),
              #("click_to_return", click_to_return_text_element),
            ]
          }
        }
        Error(_) -> [
          #("game_over", game_over_text_element),
          #("click_to_return", click_to_return_text_element),
        ]
      }
    }
    _ -> []
  }

  let svg_children = case model.game_state {
    Ended -> overlay_elements
    Countdown(_) | NotStarted ->
      list.flatten([overlay_elements, player_elements])
    _ -> player_elements
  }

  let svg_attributes = case model.game_state {
    Ended -> [
      attribute.attribute("width", int.to_string(width)),
      attribute.attribute("height", int.to_string(height)),
      attribute.tabindex(0),
      attribute.style("cursor", "pointer"),
      server_component.include(on_key_down, ["key"]),
      server_component.include(on_key_up, ["key"]),
      event.on_click(game_message.ReturnToLobby),
    ]
    _ -> [
      attribute.attribute("width", int.to_string(width)),
      attribute.attribute("height", int.to_string(height)),
      attribute.tabindex(0),
      server_component.include(on_key_down, ["key"]),
      server_component.include(on_key_up, ["key"]),
    ]
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
      svg_attributes,
      svg_children,
    )])
}

fn overlay_text_with_index(
  text: String,
  idx: Int,
  total: Int,
) -> #(String, Element(GameMsg)) {
  let offset = 50.0
  let spacing = 50.0
  let percentage =
    offset +. { spacing *. int.to_float(idx + 1) /. int.to_float(total + 1) }
  let y = float.to_string(percentage) <> "%"
  let text_element =
    svg.text(
      [
        attribute.attribute("x", "50%"),
        attribute.attribute("y", y),
        attribute.attribute("text-anchor", "middle"),
        attribute.attribute("dominant-baseline", "middle"),
        attribute.attribute("font-size", "12"),
        attribute.attribute("font-family", "sans-serif"),
        attribute.attribute("fill", "black"),
      ],
      text,
    )
  #(text <> int.to_string(idx), text_element)
}
