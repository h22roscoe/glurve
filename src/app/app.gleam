import app/app_shared_message.{type AppSharedMsg}
import game/game.{type GameMsg}
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type Started}
import glubsub.{type Topic}
import lobby/lobby.{type LobbyMsg, PlayerReady}
import lobby/lobby_manager.{type LobbyManagerMsg, CreateLobby}
import lustre.{type App}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre/server_component

pub type StartArgs {
  StartArgs(
    user_id: String,
    topic: Topic(AppSharedMsg),
    lobby_manager: Started(Subject(LobbyManagerMsg)),
  )
}

pub opaque type AppMsg {
  LobbyManagerMsg(LobbyManagerMsg)
  LobbyMsg(LobbyMsg)
  GameMsg(GameMsg)
}

pub type AppState {
  InLobby
  InGame
}

pub type AppModel {
  AppModel(
    state: AppState,
    lobbies: dict.Dict(String, Started(Subject(lobby.LobbyMsg))),
    current_lobby: Option(String),
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
  case model.state {
    InLobby -> view_lobby(model.current_lobby)
    InGame -> view_game(model.current_lobby)
  }
}

fn view_lobby(current_lobby: Option(String)) -> Element(AppMsg) {
  html.html([attribute.lang("en")], [
    html.head([], [
      html.meta([attribute.charset("utf-8")]),
      html.meta([
        attribute.name("viewport"),
        attribute.content("width=device-width, initial-scale=1"),
      ]),
      html.title([], "Glurve Fever - Lobby"),
      html.link([
        attribute.rel("stylesheet"),
        attribute.href("/static/lobby.css"),
      ]),
    ]),
    html.body([], [
      html.div([attribute.class("container")], [
        html.div([attribute.class("header")], [
          html.h1([], [html.text("🎮 Glurve Fever Lobby")]),
          html.p([], [html.text("Create or join a multiplayer game")]),
        ]),
        html.div([attribute.class("content")], [
          html.div([attribute.class("section")], [
            html.h2([], [html.text("Create New Game")]),
            html.form([attribute.id("create-form")], [
              html.div([attribute.class("form-group")], [
                html.label([attribute.for("game-name")], [
                  html.text("Game Name"),
                ]),
                html.input([
                  attribute.type_("text"),
                  attribute.id("game-name"),
                  attribute.placeholder("Enter game name"),
                  attribute.required(True),
                ]),
              ]),
              html.button(
                [
                  attribute.type_("submit"),
                  attribute.class("btn"),
                  event.on_click(LobbyManagerMsg(CreateLobby("test", 4))),
                ],
                [html.text("Create Game")],
              ),
            ]),
            html.div(
              [
                attribute.class("section"),
                attribute.style("margin-top", "20px"),
              ],
              [
                html.h2([], [html.text("Quick Actions")]),
                html.button(
                  [
                    attribute.id("refresh-games"),
                    attribute.class("btn btn-secondary"),
                  ],
                  [html.text("Refresh Games")],
                ),
                html.button(
                  [
                    attribute.id("leave-game"),
                    attribute.class("btn btn-secondary"),
                    attribute.style("margin-left", "10px"),
                  ],
                  [html.text("Leave Current Game")],
                ),
              ],
            ),
          ]),
          html.div([attribute.class("section")], [
            html.h2([], [html.text("Current Game")]),
            html.div([attribute.id("current-game-info")], [
              case current_lobby {
                Some(lobby_id) ->
                  html.div([attribute.class("game-item current-game")], [
                    html.div([attribute.class("game-info")], [
                      html.h3([], [html.text("🎯 Current Game: test")]),
                      html.p([], [html.text("Players: 0/4 • Status: test")]),
                    ]),
                    html.button(
                      [
                        attribute.class("btn"),
                        event.on_click(LobbyMsg(PlayerReady(player_id))),
                      ],
                      [html.text("Ready")],
                    ),
                  ])
                None ->
                  html.p([attribute.style("color", "#718096")], [
                    html.text("Join a game to start playing!"),
                  ])
              },
            ]),
          ]),
          html.div([attribute.class("section")], [
            html.h2([], [html.text("Available Games")]),
            html.div(
              [attribute.id("games-list"), attribute.class("game-list")],
              [
                html.p([attribute.style("color", "#718096")], [
                  html.text("Loading games..."),
                ]),
              ],
            ),
          ]),
        ]),
        html.div([attribute.id("status"), attribute.class("status")], []),
      ]),
      html.script([attribute.src("/static/lobby.js")], ""),
    ]),
  ])
}

fn view_game(current_lobby: Option(String)) -> Element(AppMsg) {
  case current_lobby {
    Some(lobby_id) ->
      server_component.element([server_component.route("/ws" <> lobby_id)], [])
    None -> html.div([], [])
  }
}
