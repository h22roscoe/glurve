import game/game_message
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import glubsub
import gluid

pub type GameInfo {
  GameInfo(
    id: String,
    name: String,
    player_count: Int,
    max_players: Int,
    status: GameStatus,
    topic: glubsub.Topic(game_message.SharedMsg),
  )
}

pub fn game_info_to_json(game_info: GameInfo) -> Json {
  json.object([
    #("id", json.string(game_info.id)),
    #("name", json.string(game_info.name)),
    #("player_count", json.int(game_info.player_count)),
    #("max_players", json.int(game_info.max_players)),
    #("status", json.string(game_status_to_string(game_info.status))),
  ])
}

pub type GameStatus {
  // In lobby, waiting for players
  Waiting
  // Game in progress
  Playing
  // Game has finished
  Finished
}

pub fn game_status_to_string(status: GameStatus) -> String {
  case status {
    Waiting -> "Waiting"
    Playing -> "Playing"
    Finished -> "Finished"
  }
}

pub type LobbyManagerState {
  LobbyManagerState(
    // game_id -> game_info
    games: Dict(String, GameInfo),
    // player_id -> game_id
    player_games: Dict(String, String),
  )
}

pub type LobbyManagerMsg {
  CreateGame(
    player_id: String,
    game_name: String,
    reply_with: process.Subject(Result(GameInfo, String)),
  )
  JoinGame(
    player_id: String,
    game_id: String,
    reply_with: process.Subject(Result(GameInfo, String)),
  )
  GetGame(game_id: String, reply_with: process.Subject(option.Option(GameInfo)))
  LeaveGame(player_id: String, reply_with: process.Subject(Result(Nil, String)))
  ListGames(reply_with: process.Subject(List(GameInfo)))
  GetPlayerGame(
    player_id: String,
    reply_with: process.Subject(option.Option(GameInfo)),
  )
  PlayerDisconnected(player_id: String)
  RemoveEmptyGames
}

pub fn start(subject: process.Subject(LobbyManagerMsg)) -> process.Pid {
  let initial_state =
    LobbyManagerState(games: dict.new(), player_games: dict.new())

  process.spawn(fn() { loop(initial_state, subject) })
}

fn loop(
  state: LobbyManagerState,
  subject: process.Subject(LobbyManagerMsg),
) -> Nil {
  let msg = process.receive_forever(from: subject)

  let new_state = case msg {
    CreateGame(player_id, game_name, reply_with) ->
      handle_create_game(state, player_id, game_name, reply_with)

    JoinGame(player_id, game_id, reply_with) ->
      handle_join_game(state, player_id, game_id, reply_with)

    GetGame(game_id, reply_with) -> handle_get_game(state, game_id, reply_with)

    LeaveGame(player_id, reply_with) ->
      handle_leave_game(state, player_id, reply_with)

    ListGames(reply_with) -> handle_list_games(state, reply_with)

    GetPlayerGame(player_id, reply_with) ->
      handle_get_player_game(state, player_id, reply_with)

    PlayerDisconnected(player_id) ->
      handle_player_disconnected(state, player_id)

    RemoveEmptyGames -> handle_remove_empty_games(state)
  }

  loop(new_state, subject)
}

fn handle_create_game(
  state: LobbyManagerState,
  player_id: String,
  game_name: String,
  reply_with: process.Subject(Result(GameInfo, String)),
) -> LobbyManagerState {
  // Check if player is already in a game
  case dict.get(state.player_games, player_id) {
    Ok(_) -> {
      process.send(reply_with, Error("Player already in a game"))
      state
    }
    Error(_) -> {
      let game_id = gluid.guidv4()
      let assert Ok(topic) = glubsub.new_topic()

      let game_info =
        GameInfo(
          id: game_id,
          name: game_name,
          player_count: 1,
          max_players: 4,
          // Default max players
          status: Waiting,
          topic: topic,
        )

      let new_games = dict.insert(state.games, game_id, game_info)
      let new_player_games = dict.insert(state.player_games, player_id, game_id)

      process.send(reply_with, Ok(game_info))

      LobbyManagerState(games: new_games, player_games: new_player_games)
    }
  }
}

fn handle_join_game(
  state: LobbyManagerState,
  player_id: String,
  game_id: String,
  reply_with: process.Subject(Result(GameInfo, String)),
) -> LobbyManagerState {
  // Check if player is already in a game
  case dict.get(state.player_games, player_id) {
    Ok(_) -> {
      process.send(reply_with, Error("Player already in a game"))
      state
    }
    Error(_) -> {
      case dict.get(state.games, game_id) {
        Error(_) -> {
          process.send(reply_with, Error("Game not found"))
          state
        }
        Ok(game_info) -> {
          case game_info.status {
            Playing -> {
              process.send(reply_with, Error("Game already in progress"))
              state
            }
            Finished -> {
              process.send(reply_with, Error("Game has finished"))
              state
            }
            Waiting -> {
              case game_info.player_count >= game_info.max_players {
                True -> {
                  process.send(reply_with, Error("Game is full"))
                  state
                }
                False -> {
                  let updated_game =
                    GameInfo(
                      ..game_info,
                      player_count: game_info.player_count + 1,
                    )

                  let new_games =
                    dict.insert(state.games, game_id, updated_game)
                  let new_player_games =
                    dict.insert(state.player_games, player_id, game_id)

                  process.send(reply_with, Ok(updated_game))

                  LobbyManagerState(
                    games: new_games,
                    player_games: new_player_games,
                  )
                }
              }
            }
          }
        }
      }
    }
  }
}

fn handle_get_game(
  state: LobbyManagerState,
  game_id: String,
  reply_with: process.Subject(option.Option(GameInfo)),
) -> LobbyManagerState {
  let game_info = dict.get(state.games, game_id)
  case game_info {
    Error(_) -> process.send(reply_with, None)
    Ok(game_info) -> process.send(reply_with, Some(game_info))
  }
  state
}

fn handle_leave_game(
  state: LobbyManagerState,
  player_id: String,
  reply_with: process.Subject(Result(Nil, String)),
) -> LobbyManagerState {
  case dict.get(state.player_games, player_id) {
    Error(_) -> {
      process.send(reply_with, Error("Player not in any game"))
      state
    }
    Ok(game_id) -> {
      let new_player_games = dict.delete(state.player_games, player_id)

      case dict.get(state.games, game_id) {
        Error(_) -> {
          process.send(reply_with, Ok(Nil))
          LobbyManagerState(..state, player_games: new_player_games)
        }
        Ok(game_info) -> {
          let updated_game =
            GameInfo(..game_info, player_count: game_info.player_count - 1)

          let new_games = case updated_game.player_count <= 0 {
            True -> dict.delete(state.games, game_id)
            False -> dict.insert(state.games, game_id, updated_game)
          }

          process.send(reply_with, Ok(Nil))

          LobbyManagerState(games: new_games, player_games: new_player_games)
        }
      }
    }
  }
}

fn handle_list_games(
  state: LobbyManagerState,
  reply_with: process.Subject(List(GameInfo)),
) -> LobbyManagerState {
  let games_list =
    dict.values(state.games)
    |> list.filter(fn(game) { game.status == Waiting })

  process.send(reply_with, games_list)
  state
}

fn handle_get_player_game(
  state: LobbyManagerState,
  player_id: String,
  reply_with: process.Subject(option.Option(GameInfo)),
) -> LobbyManagerState {
  let game_info =
    dict.get(state.player_games, player_id)
    |> result.try(dict.get(state.games, _))
    |> option.from_result

  process.send(reply_with, game_info)
  state
}

fn handle_player_disconnected(
  state: LobbyManagerState,
  player_id: String,
) -> LobbyManagerState {
  case dict.get(state.player_games, player_id) {
    Error(_) -> state
    Ok(game_id) -> {
      let new_player_games = dict.delete(state.player_games, player_id)

      case dict.get(state.games, game_id) {
        Error(_) -> LobbyManagerState(..state, player_games: new_player_games)
        Ok(game_info) -> {
          let updated_game =
            GameInfo(..game_info, player_count: game_info.player_count - 1)

          let new_games = case updated_game.player_count <= 0 {
            True -> dict.delete(state.games, game_id)
            False -> dict.insert(state.games, game_id, updated_game)
          }

          LobbyManagerState(games: new_games, player_games: new_player_games)
        }
      }
    }
  }
}

fn handle_remove_empty_games(state: LobbyManagerState) -> LobbyManagerState {
  let new_games =
    dict.filter(state.games, fn(_, game_info) { game_info.player_count > 0 })

  LobbyManagerState(..state, games: new_games)
}

pub fn create_game(
  manager: process.Subject(LobbyManagerMsg),
  player_id: String,
  game_name: String,
) -> Result(GameInfo, String) {
  process.call(manager, 5000, CreateGame(player_id, game_name, _))
}

pub fn join_game(
  manager: process.Subject(LobbyManagerMsg),
  player_id: String,
  game_id: String,
) -> Result(GameInfo, String) {
  process.call(manager, 5000, JoinGame(player_id, game_id, _))
}

pub fn leave_game(
  manager: process.Subject(LobbyManagerMsg),
  player_id: String,
) -> Result(Nil, String) {
  process.call(manager, 5000, LeaveGame(player_id, _))
}

pub fn list_games(manager: process.Subject(LobbyManagerMsg)) -> List(GameInfo) {
  process.call(manager, 5000, ListGames)
}

pub fn get_player_game(
  manager: process.Subject(LobbyManagerMsg),
  player_id: String,
) -> option.Option(GameInfo) {
  process.call(manager, 5000, GetPlayerGame(player_id, _))
}

pub fn get_game(
  manager: process.Subject(LobbyManagerMsg),
  game_id: String,
) -> option.Option(GameInfo) {
  process.call(manager, 5000, GetGame(game_id, _))
}
