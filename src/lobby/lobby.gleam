import game/game_shared_message.{type GameSharedMsg}
import gleam/erlang/process.{type Subject}
import gleam/list
import gleam/otp/actor.{type Started}
import gleam/set.{type Set}
import glubsub.{type Topic}
import gluid
import player/colour
import prng/random
import shared_messages.{
  type AppSharedMsg, AllPlayersReady, LobbyClosed, LobbyJoined, LobbyLeft,
  LobbySharedMsg, PlayerBecameNotReady, PlayerBecameReady, PlayerExitedGame,
  PlayerHasPickedColour, PlayerIsChangingColour,
}

pub type Player {
  Player(
    id: String,
    name: String,
    colour: colour.Colour,
    status: PlayerStatus,
    score: Int,
  )
}

pub type PlayerStatus {
  Ready
  NotReady
  PickingColour
  SettingName
  InGame
}

pub type LobbyMsg {
  JoinLobby(player: Player, lobby_id: String)
  LeaveLobby(player: Player)
  PlayerReady(player: Player)
  PlayerNotReady(player: Player)
  PlayerChangingColour(player: Player)
  PlayerPickedColour(player: Player, colour: colour.Colour)
  ExitGame(player: Player)
  GetGameTopic(reply_with: Subject(Topic(GameSharedMsg)))
  GetLobbyInfo(reply_with: Subject(LobbyInfo))
  CloseLobby
}

pub type LobbyInfo {
  LobbyInfo(
    code: String,
    name: String,
    players: Set(Player),
    max_players: Int,
    status: LobbyStatus,
    host_id: String,
    map: String,
    mode: String,
    region: String,
    topic: Topic(AppSharedMsg(LobbyMsg)),
    game_topic: Topic(GameSharedMsg),
  )
}

pub type LobbyStatus {
  Waiting
  Full
  Playing
}

pub fn start(
  name: String,
  host_id: String,
  max_players: Int,
  map: String,
  mode: String,
  region: String,
  topic: Topic(AppSharedMsg(LobbyMsg)),
) -> Started(Subject(LobbyMsg)) {
  let assert Ok(game_topic) = glubsub.new_topic()
  let state =
    LobbyInfo(
      room_code(),
      name,
      set.new(),
      max_players,
      Waiting,
      host_id,
      map,
      mode,
      region,
      topic,
      game_topic,
    )
  let assert Ok(actor) =
    actor.new(state)
    |> actor.on_message(handle_lobby_msg)
    |> actor.start()
  actor
}

pub fn status_to_string(status: LobbyStatus) -> String {
  case status {
    Waiting -> "Waiting"
    Full -> "Full"
    Playing -> "Playing"
  }
}

pub fn player_status_to_string(status: PlayerStatus) -> String {
  case status {
    Ready -> "Ready"
    NotReady -> "Not Ready"
    PickingColour -> "Picking Colour"
    SettingName -> "Setting Name"
    InGame -> "In Game"
  }
}

fn handle_lobby_msg(
  state: LobbyInfo,
  msg: LobbyMsg,
) -> actor.Next(LobbyInfo, LobbyMsg) {
  case msg {
    JoinLobby(player, lobby_id) if lobby_id == state.name -> {
      let used_colours =
        state.players
        |> set.to_list()
        |> list.map(fn(p) { p.colour })
        |> set.from_list()

      let available_colours =
        colour.all()
        |> set.difference(used_colours)
        |> set.to_list()

      let gen = random.uniform(colour.Red, available_colours)
      let colour = random.random_sample(gen)
      let new_player = Player(..player, colour: colour)

      case state.status {
        Waiting -> {
          let new_info =
            LobbyInfo(..state, players: set.insert(state.players, new_player))
          let num_players = set.size(new_info.players)
          let assert Ok(_) =
            glubsub.broadcast(
              state.topic,
              LobbySharedMsg(LobbyJoined(new_player.id, state.name)),
            )
          case num_players {
            _ if num_players >= state.max_players -> {
              actor.continue(LobbyInfo(..new_info, status: Full))
            }
            _ -> actor.continue(new_info)
          }
        }
        _ -> actor.continue(state)
      }
    }
    JoinLobby(_, _) -> {
      actor.continue(state)
    }
    LeaveLobby(player) -> {
      let is_host = player.id == state.host_id
      let new_players = set.delete(state.players, player)
      let new_status = case set.size(new_players) < state.max_players {
        True -> Waiting
        False -> state.status
      }
      let new_info =
        LobbyInfo(..state, players: new_players, status: new_status)
      case is_host {
        True -> {
          let assert Ok(_) =
            glubsub.broadcast(state.topic, LobbySharedMsg(LobbyClosed))
          actor.stop()
        }
        False -> {
          let assert Ok(_) =
            glubsub.broadcast(state.topic, LobbySharedMsg(LobbyLeft(player.id)))
          actor.continue(new_info)
        }
      }
    }
    PlayerReady(player) -> {
      let new_players =
        set.map(state.players, fn(p) {
          case p.id == player.id {
            True -> Player(..p, status: Ready)
            False -> p
          }
        })

      let all_ready =
        set.to_list(new_players)
        |> list.all(fn(p) { p.status == Ready })

      case all_ready {
        True -> {
          let assert Ok(_) =
            glubsub.broadcast(state.topic, LobbySharedMsg(AllPlayersReady))
          let players_in_game =
            set.map(new_players, fn(p) { Player(..p, status: InGame) })
          let new_state =
            LobbyInfo(..state, players: players_in_game, status: Playing)
          actor.continue(new_state)
        }
        False -> {
          let assert Ok(_) =
            glubsub.broadcast(
              state.topic,
              LobbySharedMsg(PlayerBecameReady(player.id)),
            )
          actor.continue(LobbyInfo(..state, players: new_players))
        }
      }
    }
    PlayerNotReady(player) -> {
      let new_players =
        set.map(state.players, fn(p) {
          case p.id == player.id {
            True -> Player(..p, status: NotReady)
            False -> p
          }
        })
      let new_info = LobbyInfo(..state, players: new_players)
      let assert Ok(_) =
        glubsub.broadcast(
          state.topic,
          LobbySharedMsg(PlayerBecameNotReady(player.id)),
        )
      actor.continue(new_info)
    }
    PlayerChangingColour(player) -> {
      let new_players =
        set.map(state.players, fn(p) {
          case p.id == player.id {
            True -> Player(..p, status: PickingColour)
            False -> p
          }
        })
      let assert Ok(_) =
        glubsub.broadcast(
          state.topic,
          LobbySharedMsg(PlayerIsChangingColour(player.id)),
        )
      actor.continue(LobbyInfo(..state, players: new_players))
    }
    PlayerPickedColour(player, colour) -> {
      let new_players =
        set.map(state.players, fn(p) {
          case p.id == player.id {
            True -> Player(..p, colour: colour, status: NotReady)
            False -> p
          }
        })
      let assert Ok(_) =
        glubsub.broadcast(
          state.topic,
          LobbySharedMsg(PlayerHasPickedColour(player.id, colour)),
        )
      actor.continue(LobbyInfo(..state, players: new_players))
    }
    ExitGame(player) -> {
      let new_players =
        set.map(state.players, fn(p) {
          case p.id == player.id {
            True -> Player(..p, status: NotReady)
            False -> p
          }
        })
      let new_info = LobbyInfo(..state, players: new_players)
      let assert Ok(_) =
        glubsub.broadcast(
          state.topic,
          LobbySharedMsg(PlayerExitedGame(player.id)),
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

pub fn join_lobby(
  subject: Subject(LobbyMsg),
  player: Player,
  lobby_id: String,
) -> Nil {
  actor.send(subject, JoinLobby(player, lobby_id))
}

pub fn leave_lobby(subject: Subject(LobbyMsg), player: Player) -> Nil {
  actor.send(subject, LeaveLobby(player))
}

pub fn player_ready(subject: Subject(LobbyMsg), player: Player) -> Nil {
  actor.send(subject, PlayerReady(player))
}

pub fn player_not_ready(subject: Subject(LobbyMsg), player: Player) -> Nil {
  actor.send(subject, PlayerNotReady(player))
}

pub fn player_changing_colour(subject: Subject(LobbyMsg), player: Player) -> Nil {
  actor.send(subject, PlayerChangingColour(player))
}

pub fn player_picked_colour(
  subject: Subject(LobbyMsg),
  player: Player,
  colour: colour.Colour,
) -> Nil {
  actor.send(subject, PlayerPickedColour(player, colour))
}

pub fn exit_game(subject: Subject(LobbyMsg), player: Player) -> Nil {
  actor.send(subject, ExitGame(player))
}

pub fn get_game_topic(
  subject: Subject(LobbyMsg),
) -> glubsub.Topic(GameSharedMsg) {
  actor.call(subject, 1000, GetGameTopic)
}

pub fn get_lobby_info(subject: Subject(LobbyMsg)) -> LobbyInfo {
  actor.call(subject, 1000, GetLobbyInfo)
}

pub fn close_lobby(subject: Subject(LobbyMsg)) -> Nil {
  actor.send(subject, CloseLobby)
}

fn room_code() -> String {
  gluid.guidv4()
}
