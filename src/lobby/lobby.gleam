import game/game_shared_message.{type GameSharedMsg}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor.{type Started}
import gleam/set.{type Set}
import glubsub.{type Topic}
import lobby/lobby_shared_message.{
  type LobbySharedMsg, AllPlayersReady, LobbyClosed, LobbyJoined, LobbyLeft,
  PlayerBecameNotReady, PlayerBecameReady,
}

pub fn start(name: String, max_players: Int) -> Started(Subject(LobbyMsg)) {
  let assert Ok(topic) = glubsub.new_topic()
  let assert Ok(game_topic) = glubsub.new_topic()
  let state =
    LobbyInfo(
      name,
      set.new(),
      set.new(),
      max_players,
      Waiting,
      topic,
      game_topic,
    )
  let assert Ok(actor) =
    actor.new(state)
    |> actor.on_message(handle_lobby_msg)
    |> actor.start()
  actor
}

pub opaque type LobbyInfo {
  LobbyInfo(
    name: String,
    players: Set(String),
    ready_players: Set(String),
    max_players: Int,
    status: LobbyStatus,
    topic: Topic(LobbySharedMsg),
    game_topic: Topic(GameSharedMsg),
  )
}

pub opaque type LobbyStatus {
  Waiting
  Full
  Playing
}

pub type LobbyMsg {
  JoinLobby(player_id: String)
  LeaveLobby(player_id: String)
  PlayerReady(player_id: String)
  PlayerNotReady(player_id: String)
  GetGameTopic(reply_with: Subject(Topic(GameSharedMsg)))
  CloseLobby
}

fn handle_lobby_msg(
  state: LobbyInfo,
  msg: LobbyMsg,
) -> actor.Next(LobbyInfo, LobbyMsg) {
  case msg {
    JoinLobby(player_id) -> {
      case state.status {
        Waiting -> {
          let new_info =
            LobbyInfo(..state, players: set.insert(state.players, player_id))
          let num_players = set.size(new_info.players)
          let assert Ok(_) =
            glubsub.broadcast(state.topic, LobbyJoined(player_id))
          case num_players {
            _ if num_players >= state.max_players -> {
              actor.continue(LobbyInfo(..new_info, status: Full))
            }
            _ -> actor.continue(state)
          }
        }
        _ -> actor.continue(state)
      }
    }
    LeaveLobby(player_id) -> {
      let new_players = set.delete(state.players, player_id)
      let new_ready_players = set.delete(state.ready_players, player_id)
      let new_status = case set.size(new_players) < state.max_players {
        True -> Waiting
        False -> state.status
      }
      let new_info =
        LobbyInfo(
          ..state,
          players: new_players,
          ready_players: new_ready_players,
          status: new_status,
        )
      let assert Ok(_) = glubsub.broadcast(state.topic, LobbyLeft(player_id))
      actor.continue(new_info)
    }
    PlayerReady(player_id) -> {
      let total_players = set.size(state.players)
      let new_ready_players = set.insert(state.ready_players, player_id)

      let all_ready = set.size(new_ready_players) == total_players
      case all_ready {
        True -> {
          let assert Ok(_) = glubsub.broadcast(state.topic, AllPlayersReady)
          let new_state =
            LobbyInfo(
              ..state,
              status: Playing,
              ready_players: new_ready_players,
            )
          actor.continue(new_state)
        }
        False -> {
          let assert Ok(_) =
            glubsub.broadcast(state.topic, PlayerBecameReady(player_id))
          actor.continue(LobbyInfo(..state, ready_players: new_ready_players))
        }
      }
    }
    PlayerNotReady(player_id) -> {
      let new_info =
        LobbyInfo(
          ..state,
          ready_players: set.delete(state.ready_players, player_id),
        )
      let assert Ok(_) =
        glubsub.broadcast(state.topic, PlayerBecameNotReady(player_id))
      actor.continue(new_info)
    }
    GetGameTopic(reply_with) -> {
      let topic = state.game_topic
      process.send(reply_with, topic)
      actor.continue(state)
    }
    CloseLobby -> {
      let assert Ok(_) = glubsub.broadcast(state.topic, LobbyClosed)
      actor.stop()
    }
  }
}

pub fn get_game_topic(
  subject: Subject(LobbyMsg),
) -> glubsub.Topic(GameSharedMsg) {
  actor.call(subject, 1000, GetGameTopic)
}
