import app/app_shared_message.{type AppSharedMsg}
import game/game.{type GameMsg}
import gleam/dict
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type Started}
import gleam/pair
import gleam/set
import glubsub.{type Topic}
import lobby/lobby.{type LobbyMsg, JoinLobby, LeaveLobby, PlayerReady}
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
  RecievedAppSharedMsg(AppSharedMsg)
  LobbyManagerMsg(LobbyManagerMsg)
  LobbyMsg(LobbyMsg)
}

pub type AppState {
  InLobby
  InGame
}

pub type AppModel {
  AppModel(
    state: AppState,
    player_id: String,
    lobbies: dict.Dict(String, Started(Subject(lobby.LobbyMsg))),
    current_lobby: Option(String),
  )
}

pub fn component() -> App(StartArgs, AppModel, AppMsg) {
  lustre.application(init, update, view)
}

fn subscribe(
  topic: glubsub.Topic(topic),
  on_msg handle_msg: fn(topic) -> msg,
) -> Effect(msg) {
  use _dispatch, subject <- server_component.select

  let assert Ok(_) = glubsub.subscribe(topic, subject)

  let selector =
    process.new_selector()
    |> process.select_map(subject, handle_msg)

  selector
}

fn init(args: StartArgs) -> #(AppModel, Effect(AppMsg)) {
  let model =
    AppModel(
      state: InLobby,
      player_id: args.user_id,
      lobbies: dict.new(),
      current_lobby: None,
    )
  #(model, subscribe(args.topic, RecievedAppSharedMsg))
}

fn update(model: AppModel, msg: AppMsg) -> #(AppModel, Effect(AppMsg)) {
  case msg {
    RecievedAppSharedMsg(r) -> update_shared_msg(model, r)
    LobbyManagerMsg(l) -> update_lobby_manager_msg(model, l)
    LobbyMsg(l) -> update_lobby_msg(model, l)
  }
}

fn update_shared_msg(
  model: AppModel,
  msg: AppSharedMsg,
) -> #(AppModel, Effect(AppMsg)) {
  todo
}

fn update_lobby_manager_msg(
  model: AppModel,
  msg: LobbyManagerMsg,
) -> #(AppModel, Effect(AppMsg)) {
  todo
}

fn update_lobby_msg(
  model: AppModel,
  msg: LobbyMsg,
) -> #(AppModel, Effect(AppMsg)) {
  todo
}

fn view(model: AppModel) -> Element(AppMsg) {
  case model.state {
    InLobby -> view_lobby(model)
    InGame -> view_game(model)
  }
}

fn view_lobby(model: AppModel) -> Element(AppMsg) {
  let player_id = model.player_id
  let current_lobby = model.current_lobby
  let lobbies = model.lobbies
  let num_lobbies = dict.size(lobbies)
  let lobbies_list = case num_lobbies {
    0 ->
      html.p([attribute.style("color", "#718096")], [
        html.text("Loading lobbies..."),
      ])
    _ ->
      html.div(
        [attribute.id("lobbies-list"), attribute.class("lobby-list")],
        {
          use lobby_id, lobby <- dict.map_values(lobbies)
          let lobby_state = lobby.get_lobby_info(lobby.data)
          html.div([attribute.class("lobby-item")], [
            html.div([attribute.class("lobby-info")], [
              html.h3([], [html.text(lobby_id)]),
              html.p([], [
                html.text(
                  "Players: "
                  <> int.to_string(set.size(lobby_state.players))
                  <> "/"
                  <> int.to_string(lobby_state.max_players)
                  <> " • Status: "
                  <> lobby.status_to_string(lobby_state.status),
                ),
              ]),
            ]),
            html.button(
              [
                attribute.class("btn"),
                event.on_click(LobbyMsg(JoinLobby(lobby_id))),
              ],
              [html.text("Join")],
            ),
          ])
        }
          |> dict.to_list
          |> list.map(pair.second),
      )
  }
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
          html.h1([], [html.text("🎮 Glurve Fever")]),
          html.p([], [html.text("Create a lobby or join an existing one")]),
        ]),
        html.div([attribute.class("content")], [
          html.div([attribute.class("section")], [
            html.h2([], [html.text("Create New Lobby")]),
            html.form([attribute.id("create-form")], [
              html.div([attribute.class("form-group")], [
                html.label([attribute.for("lobby-name")], [
                  html.text("Lobby Name"),
                ]),
                view_lobby_name_input(create_lobby),
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
          ]),
          html.div([attribute.class("section")], [
            html.h2([], [html.text("Current Lobby")]),
            html.div([attribute.id("current-lobby-info")], [
              case current_lobby {
                Some(lobby_id) -> {
                  let assert Ok(lobby) = dict.get(lobbies, lobby_id)
                  let lobby_state = lobby.get_lobby_info(lobby.data)
                  html.div([attribute.class("lobby-item current-lobby")], [
                    html.div([attribute.class("lobby-info")], [
                      html.h3([], [html.text("🎯 Current Lobby: " <> lobby_id)]),
                      html.p([], [
                        html.text(
                          "Ready players: "
                          <> int.to_string(set.size(lobby_state.ready_players))
                          <> "/"
                          <> int.to_string(set.size(lobby_state.players))
                          <> " • Status: "
                          <> lobby.status_to_string(lobby_state.status),
                        ),
                      ]),
                    ]),
                    html.button(
                      [
                        attribute.class("btn"),
                        event.on_click(LobbyMsg(PlayerReady(player_id))),
                      ],
                      [html.text("Ready")],
                    ),
                    html.button(
                      [
                        attribute.id("leave-lobby"),
                        attribute.class("btn btn-secondary"),
                        attribute.style("margin-left", "10px"),
                        event.on_click(LobbyMsg(LeaveLobby(player_id))),
                      ],
                      [html.text("Leave lobby")],
                    ),
                  ])
                }
                None ->
                  html.p([attribute.style("color", "#718096")], [
                    html.text("Join a lobby to start playing!"),
                  ])
              },
            ]),
          ]),
          html.div([attribute.class("section")], [
            html.h2([], [html.text("Available Lobbies")]),
            html.div(
              [attribute.id("lobbies-list"), attribute.class("lobby-list")],
              [lobbies_list],
            ),
          ]),
        ]),
        html.div([attribute.id("status"), attribute.class("status")], []),
      ]),
    ]),
  ])
}

fn create_lobby(name: String) -> AppMsg {
  LobbyManagerMsg(CreateLobby(name, 4))
}

fn view_lobby_name_input(
  on_submit handle_keydown: fn(String) -> msg,
) -> Element(msg) {
  let on_keydown =
    event.on("keydown", {
      use key <- decode.field("key", decode.string)
      use value <- decode.subfield(["target", "value"], decode.string)

      case key {
        "Enter" if value != "" -> decode.success(handle_keydown(value))
        _ -> decode.failure(handle_keydown(""), "")
      }
    })
    |> server_component.include(["key", "target.value"])

  html.input([
    attribute.class("input"),
    attribute.type_("text"),
    attribute.id("lobby-name"),
    attribute.placeholder("Enter lobby name"),
    attribute.required(True),
    on_keydown,
  ])
}

fn view_game(model: AppModel) -> Element(AppMsg) {
  case model.current_lobby {
    Some(lobby_id) ->
      server_component.element([server_component.route("/ws" <> lobby_id)], [])
    None -> html.div([], [])
  }
}
