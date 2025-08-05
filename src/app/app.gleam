import game/game
import game/game_message
import gleam/erlang/process.{type Selector, type Subject}
import gleam/json
import gleam/option.{type Option, Some}
import gleam/otp/actor
import glubsub
import lobby/lobby
import lobby/lobby_manager
import lustre
import lustre/server_component
import mist

pub type StartArgs {
  StartArgs(
    lobby_manager: actor.Started(process.Subject(lobby_manager.LobbyManagerMsg)),
  )
}

pub type AppMsg {
  LobbyManagerMsg(lobby_manager.LobbyManagerMsg)
  LobbyMsg(lobby.LobbyMsg)
  GameMsg(game_message.GameMsg)
}

pub type AppState {
  InLobby
  InGame(game.GameState)
}

pub type AppModel {
  AppModel(
    state: AppState,
    lobby: Option(lobby.LobbyInfo),
    game: Option(game.Model),
  )
}
