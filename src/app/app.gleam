import game/game
import game/game_message
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option}
import gleam/otp/actor.{type Started}
import glubsub.{type Topic}
import lobby/lobby
import lobby/lobby_manager
import lustre.{type App}
import lustre/effect.{type Effect}
import lustre/element.{type Element}

pub type StartArgs {
  StartArgs(topic: Topic(AppSharedMsg))
}

pub type AppSharedMsg {
  RecievedLobbyManagerMsg(lobby_manager.LobbyManagerSharedMsg)
  RecievedLobbyMsg(lobby.LobbySharedMsg)
  RecievedGameMsg(game_message.GameSharedMsg)
}

pub opaque type AppMsg {
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
    lobbies: dict.Dict(String, Started(Subject(lobby.LobbyMsg))),
    current_lobby: Option(String),
    game: Option(game.Model),
  )
}

pub fn component() -> App(StartArgs, AppModel, AppMsg) {
  lustre.application(init, update, view)
}

fn init(args: StartArgs) -> #(AppModel, Effect(AppMsg)) {
  todo
}

fn update(model: AppModel, msg: AppMsg) -> #(AppModel, Effect(AppMsg)) {
  todo
}

fn view(model: AppModel) -> Element(AppMsg) {
  todo
}
