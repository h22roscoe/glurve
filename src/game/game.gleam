import game/game_shared_message.{type GameSharedMsg}
import game/time
import gleam/dict
import gleam/erlang/process
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam_community/colour
import gleam_community/maths
import glubsub
import lobby/lobby.{type LobbyMsg}
import lustre.{type App}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/keyed
import lustre/element/svg
import lustre/event
import lustre/server_component
import player/player.{tail_radius}
import prng/seed.{type Seed}
import shared_messages.{type AppSharedMsg}

const head_size = 10.0

const tick_delay_ms = 10

pub type StartArgs {
  StartArgs(
    lobby_id: String,
    app_topic: glubsub.Topic(AppSharedMsg(LobbyMsg)),
    user_id: String,
    topic: glubsub.Topic(GameSharedMsg),
    players: dict.Dict(String, player.Player),
    seed: Seed,
  )
}

pub fn component() -> App(StartArgs, Model, GameMsg) {
  lustre.application(init, update, view)
}

pub type GameMsg {
  RecievedSharedMsg(GameSharedMsg)
  NewTimer(time.TimerID)
  NewCountdownTimer(time.TimerID)
  CountdownTick
  Tick
  KeyDown(String)
  KeyUp(String)
  EndGame
  NoOp
}

pub type Model {
  Model(
    lobby_id: String,
    app_topic: glubsub.Topic(AppSharedMsg(LobbyMsg)),
    topic: glubsub.Topic(GameSharedMsg),
    game_state: GameState,
    player_id: String,
    players: dict.Dict(String, player.Player),
    timer: Option(time.TimerID),
    countdown_timer: Option(time.TimerID),
    seed: Seed,
    board_width: Int,
    board_height: Int,
  )
}

pub type GameState {
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

fn compute_board_size(num_players: Int) -> Int {
  let base = 480
  let per_player = 40
  let extra = int.max(0, num_players - 2) * per_player
  let size = base + extra
  // Clamp to a sensible range
  case size {
    _ if size < 480 -> 480
    _ if size > 900 -> 900
    _ -> size
  }
}

fn init(start_args: StartArgs) -> #(Model, Effect(GameMsg)) {
  let num_players = dict.size(start_args.players)
  let board = compute_board_size(num_players)
  let model =
    Model(
      lobby_id: start_args.lobby_id,
      app_topic: start_args.app_topic,
      topic: start_args.topic,
      game_state: Countdown(3),
      player_id: start_args.user_id,
      players: start_args.players,
      timer: None,
      countdown_timer: None,
      seed: start_args.seed,
      board_width: board,
      board_height: board,
    )

  #(
    model,
    effect.batch([
      subscribe(start_args.topic, RecievedSharedMsg),
      countdown_effect(),
      tick_effect(),
    ]),
  )
}

fn tick_effect() -> Effect(GameMsg) {
  use dispatch <- effect.from
  case time.apply_interval(tick_delay_ms, fn() { dispatch(Tick) }) {
    Ok(timer) -> dispatch(NewTimer(timer))
    Error(_) -> Nil
  }
}

fn countdown_effect() -> Effect(GameMsg) {
  use dispatch <- effect.from
  case time.apply_interval(1000, fn() { dispatch(CountdownTick) }) {
    Ok(timer) -> dispatch(NewCountdownTimer(timer))
    Error(_) -> Nil
  }
}

fn cancel_timer(timer: Option(time.TimerID)) -> Effect(GameMsg) {
  case timer {
    Some(timer) -> {
      use dispatch <- effect.from
      let _ = time.cancel(timer)
      dispatch(NoOp)
    }
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
  shared_msg: GameSharedMsg,
) -> #(Model, Effect(GameMsg)) {
  case shared_msg {
    game_shared_message.PlayerCrashed(player_id) -> {
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

    game_shared_message.PlayerTurning(player_id, direction) -> {
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
    NewTimer(timer) -> #(Model(..model, timer: Some(timer)), effect.none())

    NewCountdownTimer(timer) -> #(
      Model(..model, countdown_timer: Some(timer)),
      effect.none(),
    )

    CountdownTick -> {
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

    RecievedSharedMsg(shared_msg) -> handle_shared_msg(model, shared_msg)

    Tick -> {
      let new_players =
        dict.map_values(model.players, fn(_, p) {
          player.update(p, model.board_height, model.board_width)
        })
      let assert Ok(this_player) = dict.get(new_players, model.player_id)
      let player_collided_with_self =
        player.check_collision_with_self(this_player)
      let player_collided_with_edges =
        player.check_collision_with_edges(
          this_player,
          model.board_height,
          model.board_width,
        )
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
          broadcast(
            model.topic,
            game_shared_message.PlayerCrashed(model.player_id),
          ),
        )
      }
    }

    KeyDown("ArrowRight") -> {
      let broadcast_msg =
        game_shared_message.PlayerTurning(model.player_id, player.Right)
      let broadcast_effect = broadcast(model.topic, broadcast_msg)

      #(
        Model(
          ..model,
          players: handle_turn(model.players, model.player_id, player.Right),
        ),
        broadcast_effect,
      )
    }

    KeyDown("ArrowLeft") -> {
      let broadcast_msg =
        game_shared_message.PlayerTurning(model.player_id, player.Left)
      let broadcast_effect = broadcast(model.topic, broadcast_msg)
      #(
        Model(
          ..model,
          players: handle_turn(model.players, model.player_id, player.Left),
        ),
        broadcast_effect,
      )
    }

    KeyDown(_) -> #(model, effect.none())

    KeyUp("ArrowLeft") | KeyUp("ArrowRight") -> {
      let broadcast_msg =
        game_shared_message.PlayerTurning(model.player_id, player.Straight)
      let broadcast_effect = broadcast(model.topic, broadcast_msg)
      #(
        Model(
          ..model,
          players: handle_turn(model.players, model.player_id, player.Straight),
        ),
        broadcast_effect,
      )
    }

    KeyUp(_) -> #(model, effect.none())

    EndGame -> {
      #(model, effect.none())
    }

    NoOp -> #(model, effect.none())
  }
}

fn view(model: Model) -> Element(GameMsg) {
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

  let player_elements = list.flat_map(dict.values(model.players), draw_player)

  let game_over_text_element =
    svg.text(
      [
        attribute.attribute("x", "50%"),
        attribute.attribute("y", "50%"),
        attribute.attribute("text-anchor", "middle"),
        attribute.attribute("dominant-baseline", "middle"),
        attribute.attribute("font-size", "24"),
        attribute.attribute("font-family", "sans-serif"),
        attribute.attribute("fill", "#f3b2ef"),
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
        attribute.attribute("fill", "#f3b2ef"),
      ],
      "You Win!",
    )

  let overlay_elements = case model.game_state {
    Countdown(count) -> {
      draw_countdown(count)
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
            True -> [#("winner", winner_text_element)]
            False -> [#("game_over", game_over_text_element)]
          }
        }
        Error(_) -> [#("game_over", game_over_text_element)]
      }
    }
    _ -> []
  }

  let svg_children = case model.game_state {
    Ended -> overlay_elements
    Countdown(_) -> list.flatten([overlay_elements, player_elements])
    _ -> player_elements
  }

  let svg_attributes = [
    attribute.attribute(
      "viewBox",
      "0 0 "
        <> int.to_string(model.board_width)
        <> " "
        <> int.to_string(model.board_height),
    ),
    // Ensure the SVG can receive focus for keyboard controls
    attribute.tabindex(0),
    attribute.autofocus(True),
    attribute.attribute("width", "100%"),
    attribute.attribute("height", "100%"),
    attribute.style("outline", "none!important"),
    server_component.include(on_key_down, ["key"]),
    server_component.include(on_key_up, ["key"]),
  ]

  element.fragment([
    keyed.namespaced(
      "http://www.w3.org/2000/svg",
      "svg",
      svg_attributes,
      svg_children,
    ),
  ])
}

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

pub fn draw_countdown(count: Int) -> List(#(String, Element(GameMsg))) {
  let countdown_colour = case colour.from_hsla(0.824, 0.73, 0.83, 0.15) {
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
