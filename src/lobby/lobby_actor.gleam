import game/game_message
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/json.{type Json}
import gleam/list
import gleam/option.{None, Some}
import gleam/otp/actor
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

pub type GameStatus {
  Waiting
  Playing
  Finished
}

pub fn game_status_to_string(status: GameStatus) -> String {
  case status {
    Waiting -> "Waiting"
    Playing -> "Playing"
    Finished -> "Finished"
  }
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

// Actor State
type State {
  State(games: Dict(String, GameInfo), player_games: Dict(String, String))
}

// Actor Messages
pub type Message {
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
  StartGame(game_id: String)
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

// Start the actor
pub fn start() -> Result(
  actor.Started(process.Subject(Message)),
  actor.StartError,
) {
  let initial_state = State(games: dict.new(), player_games: dict.new())

  actor.new(initial_state)
  |> actor.on_message(handle_message)
  |> actor.start()
}

// Start with a custom name for registration
pub fn start_named(
  name: process.Name(Message),
) -> Result(actor.Started(process.Subject(Message)), actor.StartError) {
  let initial_state = State(games: dict.new(), player_games: dict.new())

  actor.new(initial_state)
  |> actor.named(name)
  |> actor.on_message(handle_message)
  |> actor.start()
}

// Message handler
fn handle_message(state: State, message: Message) -> actor.Next(State, Message) {
  case message {
    CreateGame(player_id, game_name, reply_with) -> {
      let new_state =
        handle_create_game(state, player_id, game_name, reply_with)
      actor.continue(new_state)
    }

    JoinGame(player_id, game_id, reply_with) -> {
      let new_state = handle_join_game(state, player_id, game_id, reply_with)
      actor.continue(new_state)
    }

    StartGame(game_id) -> {
      let new_state = handle_start_game(state, game_id)
      actor.continue(new_state)
    }

    GetGame(game_id, reply_with) -> {
      let new_state = handle_get_game(state, game_id, reply_with)
      actor.continue(new_state)
    }

    LeaveGame(player_id, reply_with) -> {
      let new_state = handle_leave_game(state, player_id, reply_with)
      actor.continue(new_state)
    }

    ListGames(reply_with) -> {
      let new_state = handle_list_games(state, reply_with)
      actor.continue(new_state)
    }

    GetPlayerGame(player_id, reply_with) -> {
      let new_state = handle_get_player_game(state, player_id, reply_with)
      actor.continue(new_state)
    }

    PlayerDisconnected(player_id) -> {
      let new_state = handle_player_disconnected(state, player_id)
      actor.continue(new_state)
    }

    RemoveEmptyGames -> {
      let new_state = handle_remove_empty_games(state)
      actor.continue(new_state)
    }
  }
}

// Handler implementations (improved with better error handling)
fn handle_create_game(
  state: State,
  player_id: String,
  game_name: String,
  reply_with: process.Subject(Result(GameInfo, String)),
) -> State {
  case dict.get(state.player_games, player_id) {
    Ok(_) -> {
      process.send(reply_with, Error("Player already in a game"))
      state
    }
    Error(_) -> {
      // Better error handling for glubsub.new_topic()
      case glubsub.new_topic() {
        Ok(topic) -> {
          let game_id = gluid.guidv4()
          let game_info =
            GameInfo(
              id: game_id,
              name: game_name,
              player_count: 1,
              max_players: 4,
              status: Waiting,
              topic: topic,
            )

          let new_games = dict.insert(state.games, game_id, game_info)
          let new_player_games =
            dict.insert(state.player_games, player_id, game_id)

          process.send(reply_with, Ok(game_info))
          State(games: new_games, player_games: new_player_games)
        }
        Error(_) -> {
          process.send(reply_with, Error("Failed to create game topic"))
          state
        }
      }
    }
  }
}

fn handle_join_game(
  state: State,
  player_id: String,
  game_id: String,
  reply_with: process.Subject(Result(GameInfo, String)),
) -> State {
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

                  State(games: new_games, player_games: new_player_games)
                }
              }
            }
          }
        }
      }
    }
  }
}

fn handle_start_game(state: State, game_id: String) -> State {
  let game_info = dict.get(state.games, game_id)
  case game_info {
    Ok(game_info) -> {
      let updated_game = GameInfo(..game_info, status: Playing)
      let new_games = dict.insert(state.games, game_id, updated_game)
      State(..state, games: new_games)
    }
    Error(_) -> {
      state
    }
  }
}

fn handle_get_game(
  state: State,
  game_id: String,
  reply_with: process.Subject(option.Option(GameInfo)),
) -> State {
  let game_info = dict.get(state.games, game_id)
  case game_info {
    Error(_) -> process.send(reply_with, None)
    Ok(game_info) -> process.send(reply_with, Some(game_info))
  }
  state
}

fn handle_leave_game(
  state: State,
  player_id: String,
  reply_with: process.Subject(Result(Nil, String)),
) -> State {
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
          State(..state, player_games: new_player_games)
        }
        Ok(game_info) -> {
          let updated_game =
            GameInfo(..game_info, player_count: game_info.player_count - 1)

          let new_games = case updated_game.player_count <= 0 {
            True -> dict.delete(state.games, game_id)
            False -> dict.insert(state.games, game_id, updated_game)
          }

          process.send(reply_with, Ok(Nil))

          State(games: new_games, player_games: new_player_games)
        }
      }
    }
  }
}

fn handle_list_games(
  state: State,
  reply_with: process.Subject(List(GameInfo)),
) -> State {
  let games_list =
    dict.values(state.games)
    |> list.filter(fn(game) { game.status == Waiting })

  process.send(reply_with, games_list)
  state
}

fn handle_get_player_game(
  state: State,
  player_id: String,
  reply_with: process.Subject(option.Option(GameInfo)),
) -> State {
  let game_info =
    dict.get(state.player_games, player_id)
    |> result.try(dict.get(state.games, _))
    |> option.from_result

  process.send(reply_with, game_info)
  state
}

fn handle_player_disconnected(state: State, player_id: String) -> State {
  case dict.get(state.player_games, player_id) {
    Error(_) -> state
    Ok(game_id) -> {
      let new_player_games = dict.delete(state.player_games, player_id)

      case dict.get(state.games, game_id) {
        Error(_) -> State(..state, player_games: new_player_games)
        Ok(game_info) -> {
          let updated_game =
            GameInfo(..game_info, player_count: game_info.player_count - 1)

          let new_games = case updated_game.player_count <= 0 {
            True -> dict.delete(state.games, game_id)
            False -> dict.insert(state.games, game_id, updated_game)
          }

          State(games: new_games, player_games: new_player_games)
        }
      }
    }
  }
}

fn handle_remove_empty_games(state: State) -> State {
  let new_games =
    dict.filter(state.games, fn(_, game_info) { game_info.player_count > 0 })

  State(..state, games: new_games)
}

// Public API functions (for backward compatibility)
pub fn create_game(
  actor_subject: process.Subject(Message),
  player_id: String,
  game_name: String,
) -> Result(GameInfo, String) {
  actor.call(actor_subject, 5000, CreateGame(player_id, game_name, _))
}

pub fn join_game(
  actor_subject: process.Subject(Message),
  player_id: String,
  game_id: String,
) -> Result(GameInfo, String) {
  actor.call(actor_subject, 5000, JoinGame(player_id, game_id, _))
}

pub fn start_game(
  actor_subject: process.Subject(Message),
  game_id: String,
) -> Nil {
  actor.send(actor_subject, StartGame(game_id))
}

pub fn leave_game(
  actor_subject: process.Subject(Message),
  player_id: String,
) -> Result(Nil, String) {
  actor.call(actor_subject, 5000, LeaveGame(player_id, _))
}

pub fn list_games(actor_subject: process.Subject(Message)) -> List(GameInfo) {
  actor.call(actor_subject, 5000, ListGames)
}

pub fn get_player_game(
  actor_subject: process.Subject(Message),
  player_id: String,
) -> option.Option(GameInfo) {
  actor.call(actor_subject, 5000, GetPlayerGame(player_id, _))
}

pub fn get_game(
  actor_subject: process.Subject(Message),
  game_id: String,
) -> option.Option(GameInfo) {
  actor.call(actor_subject, 5000, GetGame(game_id, _))
}
