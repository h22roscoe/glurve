import game/game_shared_message.{type GameSharedMsg}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor.{type Started}
import gleam/set.{type Set}
import glubsub.{type Topic}
import shared_messages.{
  type AppSharedMsg, AllPlayersReady, LobbyClosed, LobbyJoined, LobbyLeft,
  LobbySharedMsg, PlayerBecameNotReady, PlayerBecameReady,
}

pub fn start(
  name: String,
  max_players: Int,
  topic: Topic(AppSharedMsg(LobbyMsg)),
) -> Started(Subject(LobbyMsg)) {
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

pub type LobbyMsg {
  JoinLobby(player_id: String, lobby_id: String)
  LeaveLobby(player_id: String)
  PlayerReady(player_id: String)
  PlayerNotReady(player_id: String)
  GetGameTopic(reply_with: Subject(Topic(GameSharedMsg)))
  GetLobbyInfo(reply_with: Subject(LobbyInfo))
  CloseLobby
}

pub type LobbyInfo {
  LobbyInfo(
    name: String,
    players: Set(String),
    ready_players: Set(String),
    max_players: Int,
    status: LobbyStatus,
    topic: Topic(AppSharedMsg(LobbyMsg)),
    game_topic: Topic(GameSharedMsg),
  )
}

pub type LobbyStatus {
  Waiting
  Full
  Playing
}

pub fn status_to_string(status: LobbyStatus) -> String {
  case status {
    Waiting -> "Waiting"
    Full -> "Full"
    Playing -> "Playing"
  }
}

fn handle_lobby_msg(
  state: LobbyInfo,
  msg: LobbyMsg,
) -> actor.Next(LobbyInfo, LobbyMsg) {
  case msg {
    JoinLobby(player_id, lobby_id) -> {
      case state.status {
        Waiting -> {
          let new_info =
            LobbyInfo(..state, players: set.insert(state.players, player_id))
          let num_players = set.size(new_info.players)
          let assert Ok(_) =
            glubsub.broadcast(
              state.topic,
              LobbySharedMsg(LobbyJoined(player_id, lobby_id)),
            )
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
      let assert Ok(_) =
        glubsub.broadcast(state.topic, LobbySharedMsg(LobbyLeft(player_id)))
      actor.continue(new_info)
    }
    PlayerReady(player_id) -> {
      let total_players = set.size(state.players)
      let new_ready_players = set.insert(state.ready_players, player_id)

      let all_ready = set.size(new_ready_players) == total_players
      case all_ready {
        True -> {
          let assert Ok(_) =
            glubsub.broadcast(state.topic, LobbySharedMsg(AllPlayersReady))
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
            glubsub.broadcast(
              state.topic,
              LobbySharedMsg(PlayerBecameReady(player_id)),
            )
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
        glubsub.broadcast(
          state.topic,
          LobbySharedMsg(PlayerBecameNotReady(player_id)),
        )
      actor.continue(new_info)
    }
    GetGameTopic(reply_with) -> {
      let topic = state.game_topic
      process.send(reply_with, topic)
      actor.continue(state)
    }
    GetLobbyInfo(reply_with) -> {
      process.send(reply_with, state)
      actor.continue(state)
    }
    CloseLobby -> {
      let assert Ok(_) =
        glubsub.broadcast(state.topic, LobbySharedMsg(LobbyClosed))
      actor.stop()
    }
  }
}

pub fn get_game_topic(
  subject: Subject(LobbyMsg),
) -> glubsub.Topic(GameSharedMsg) {
  actor.call(subject, 1000, GetGameTopic)
}

pub fn get_lobby_info(subject: Subject(LobbyMsg)) -> LobbyInfo {
  actor.call(subject, 1000, GetLobbyInfo)
}
