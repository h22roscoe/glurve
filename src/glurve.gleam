import app/app_socket
import envoy
import game/game_socket
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/http/request
import gleam/http/response
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor.{type Started}
import gleam/result
import gleam/set
import glubsub.{type Topic}
import lobby/lobby.{type LobbyMsg}
import lobby/lobby_manager.{type LobbyManagerMsg}
import mist
import player/player.{Player, Straight}
import position
import prng/seed.{type Seed}
import radiate
import router
import shared_messages.{type AppSharedMsg}
import uuid_colour
import wisp
import wisp/wisp_mist

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let env = envoy.get("ENV")
  case env {
    Ok("PROD") -> Nil
    _ -> {
      let _ =
        radiate.new()
        |> radiate.add_dir(".")
        |> radiate.start()
      Nil
    }
  }

  wisp.configure_logger()

  let assert Ok(topic) = glubsub.new_topic()
  let lobby_manager = lobby_manager.start(topic)

  let secret_key_base =
    envoy.get("SECRET_KEY_BASE")
    |> result.lazy_unwrap(fn() { wisp.random_string(64) })

  let seed = seed.random()

  let wisp_handler =
    router.handle_request
    |> wisp_mist.handler(secret_key_base)

  let overall_handler = fn(req: request.Request(mist.Connection)) -> response.Response(
    mist.ResponseData,
  ) {
    case request.path_segments(req) {
      ["ws"] -> serve_app_ws(req, topic, lobby_manager)
      ["ws", lobby_id] ->
        serve_game_ws(req, topic, lobby_id, lobby_manager, seed)
      _ -> wisp_handler(req)
    }
  }

  let assert Ok(_) =
    overall_handler
    |> mist.new
    |> mist.bind("0.0.0.0")
    |> mist.port(1234)
    |> mist.start

  process.sleep_forever()
}

// WEBSOCKET -------------------------------------------------------------------

fn serve_app_ws(
  req: request.Request(mist.Connection),
  topic: Topic(AppSharedMsg(LobbyMsg)),
  lobby_manager: Started(Subject(LobbyManagerMsg)),
) -> response.Response(mist.ResponseData) {
  let assert Some(user_id) =
    request.get_cookies(req)
    |> list.fold(None, fn(acc, c) {
      case c {
        #("glurve_user_id", id) -> Some(id)
        _ -> acc
      }
    })
    as "User ID cookie not found"

  mist.websocket(
    request: req,
    on_init: app_socket.init(_, user_id, topic, lobby_manager),
    handler: app_socket.loop_socket,
    on_close: app_socket.close_socket,
  )
}

fn serve_game_ws(
  req: request.Request(mist.Connection),
  app_topic: Topic(AppSharedMsg(LobbyMsg)),
  lobby_id: String,
  lobby_manager: Started(Subject(LobbyManagerMsg)),
  seed: Seed,
) -> response.Response(mist.ResponseData) {
  let assert Some(user_id) =
    request.get_cookies(req)
    |> list.fold(None, fn(acc, c) {
      case c {
        #("glurve_user_id", id) -> Some(id)
        _ -> acc
      }
    })
    as "User ID cookie not found"

  let l = lobby_manager.get_lobby(lobby_manager.data, lobby_id)
  let game_topic = lobby.get_game_topic(l.data)
  let lobby_info = lobby.get_lobby_info(l.data)
  let num_players = set.size(lobby_info.players)
  let #(positions, next_seed) =
    position.random_start_positions(num_players, 500, 500, seed)
  let players =
    set.to_list(lobby_info.players)
    |> list.zip(positions)
    |> list.fold(dict.new(), fn(acc, zipped) {
      let #(player, pos) = zipped
      let player =
        Player(
          id: player.id,
          colour: uuid_colour.colour_for_uuid(player.id),
          position: pos,
          speed: 0.0,
          angle: 0.0,
          tail: [],
          turning: Straight,
        )
      dict.insert(acc, player.id, player)
    })

  mist.websocket(
    request: req,
    on_init: game_socket.init(
      _,
      user_id,
      lobby_id,
      app_topic,
      game_topic,
      players,
      next_seed,
    ),
    handler: game_socket.loop_socket,
    on_close: game_socket.close_socket,
  )
}
