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
import lobby/lobby.{
  type LobbyInfo, type LobbyMsg, CloseLobby, GetGameTopic, GetLobbyInfo,
  JoinLobby, LeaveLobby, LobbyInfo, PlayerNotReady, PlayerReady,
}
import lobby/lobby_manager.{
  type LobbyManagerMsg, CreateLobby, ListLobbies, RemoveLobby,
}
import lustre.{type App}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre/server_component
import shared_messages.{
  type AppSharedMsg, type LobbyManagerSharedMsg, type LobbySharedMsg,
  AllPlayersReady, LobbyClosed, LobbyCreated, LobbyJoined, LobbyLeft,
  LobbyManagerSharedMsg, LobbyRemoved, LobbySharedMsg, PlayerBecameNotReady,
  PlayerBecameReady,
}

pub type StartArgs {
  StartArgs(
    user_id: String,
    topic: Topic(AppSharedMsg(LobbyMsg)),
    lobby_manager: Started(Subject(LobbyManagerMsg)),
  )
}

pub opaque type AppMsg {
  RecievedAppSharedMsg(AppSharedMsg(LobbyMsg))
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
    current_lobby: Option(LobbyInfo),
    lobby_manager: Started(Subject(LobbyManagerMsg)),
    topic: Topic(AppSharedMsg(LobbyMsg)),
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
      lobbies: lobby_manager.list_lobbies(args.lobby_manager.data),
      current_lobby: None,
      lobby_manager: args.lobby_manager,
      topic: args.topic,
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
  msg: AppSharedMsg(LobbyMsg),
) -> #(AppModel, Effect(AppMsg)) {
  case msg {
    LobbyManagerSharedMsg(l) -> update_lobby_manager_shared_msg(model, l)
    LobbySharedMsg(l) -> update_lobby_shared_msg(model, l)
  }
}

fn update_lobby_manager_shared_msg(
  model: AppModel,
  msg: LobbyManagerSharedMsg(LobbyMsg),
) -> #(AppModel, Effect(AppMsg)) {
  case msg {
    LobbyCreated(lobby_id, lobby) -> {
      let lobbies = dict.insert(model.lobbies, lobby_id, lobby)
      #(AppModel(..model, lobbies: lobbies), effect.none())
    }
    LobbyRemoved(lobby_id) -> {
      let lobbies = dict.delete(model.lobbies, lobby_id)
      #(AppModel(..model, lobbies: lobbies), effect.none())
    }
  }
}

fn update_lobby_shared_msg(
  model: AppModel,
  msg: LobbySharedMsg,
) -> #(AppModel, Effect(AppMsg)) {
  case model.current_lobby {
    None -> {
      case msg {
        LobbyJoined(player_id, lobby_id) if player_id == model.player_id -> {
          let assert Ok(lobby) = dict.get(model.lobbies, lobby_id)
          let lobby_info = lobby.get_lobby_info(lobby.data)
          #(AppModel(..model, current_lobby: Some(lobby_info)), effect.none())
        }
        _ -> #(model, effect.none())
      }
    }
    Some(lobby_info) -> {
      case msg {
        LobbyJoined(player_id, lobby_id) if lobby_id == lobby_info.name -> {
          let lobby_info =
            LobbyInfo(
              ..lobby_info,
              players: set.insert(lobby_info.players, player_id),
            )
          #(AppModel(..model, current_lobby: Some(lobby_info)), effect.none())
        }
        LobbyJoined(_, _) -> {
          #(model, effect.none())
        }
        LobbyLeft(player_id) -> {
          case player_id == model.player_id {
            True -> #(
              AppModel(..model, current_lobby: None, state: InLobby),
              effect.none(),
            )

            False -> {
              let lobby_info =
                LobbyInfo(
                  ..lobby_info,
                  players: set.delete(lobby_info.players, player_id),
                )
              #(
                AppModel(..model, current_lobby: Some(lobby_info)),
                effect.none(),
              )
            }
          }
        }
        PlayerBecameReady(player_id) -> {
          let lobby_info =
            LobbyInfo(
              ..lobby_info,
              ready_players: set.insert(lobby_info.ready_players, player_id),
            )
          #(AppModel(..model, current_lobby: Some(lobby_info)), effect.none())
        }
        PlayerBecameNotReady(player_id) -> {
          let lobby_info =
            LobbyInfo(
              ..lobby_info,
              ready_players: set.delete(lobby_info.ready_players, player_id),
            )
          #(AppModel(..model, current_lobby: Some(lobby_info)), effect.none())
        }
        AllPlayersReady -> {
          #(AppModel(..model, state: InGame), effect.none())
        }
        LobbyClosed -> {
          let lobbies = dict.delete(model.lobbies, lobby_info.name)
          #(
            AppModel(
              ..model,
              state: InLobby,
              current_lobby: None,
              lobbies: lobbies,
            ),
            effect.none(),
          )
        }
      }
    }
  }
}

fn update_lobby_manager_msg(
  model: AppModel,
  msg: LobbyManagerMsg,
) -> #(AppModel, Effect(AppMsg)) {
  let lobby_manager = model.lobby_manager
  case msg {
    CreateLobby(name, max_players) -> {
      #(model, create_lobby_effect(lobby_manager, name, max_players))
    }
    RemoveLobby(lobby_id) -> {
      #(model, remove_lobby_effect(lobby_manager, lobby_id))
    }
    ListLobbies(_) -> {
      let lobbies = lobby_manager.list_lobbies(lobby_manager.data)
      #(AppModel(..model, lobbies: lobbies), effect.none())
    }
  }
}

fn create_lobby_effect(
  lobby_manager: Started(Subject(LobbyManagerMsg)),
  name: String,
  max_players: Int,
) {
  use _dispatch <- effect.from
  lobby_manager.create_lobby(lobby_manager.data, name, max_players)
}

fn remove_lobby_effect(
  lobby_manager: Started(Subject(LobbyManagerMsg)),
  lobby_id: String,
) {
  use _dispatch <- effect.from
  lobby_manager.remove_lobby(lobby_manager.data, lobby_id)
}

fn update_lobby_msg(
  model: AppModel,
  msg: LobbyMsg,
) -> #(AppModel, Effect(AppMsg)) {
  case msg {
    JoinLobby(player_id, lobby_id) -> {
      #(model, join_lobby_effect(player_id, lobby_id, model.lobbies))
    }
    LeaveLobby(player_id) -> {
      case model.current_lobby {
        Some(lobby_info) -> {
          #(
            model,
            leave_lobby_effect(player_id, lobby_info.name, model.lobbies),
          )
        }
        None -> #(model, effect.none())
      }
    }
    PlayerReady(player_id) -> {
      case model.current_lobby {
        Some(lobby_info) -> {
          #(
            model,
            player_ready_effect(player_id, lobby_info.name, model.lobbies),
          )
        }
        None -> #(model, effect.none())
      }
    }
    PlayerNotReady(player_id) -> {
      #(model, player_not_ready_effect(player_id, model.topic))
    }
    GetGameTopic(_) -> {
      #(model, effect.none())
    }
    GetLobbyInfo(_) -> {
      #(model, effect.none())
    }
    CloseLobby -> {
      case model.current_lobby {
        Some(lobby_info) -> {
          #(model, close_lobby_effect(lobby_info.name, model.lobbies))
        }
        None -> #(model, effect.none())
      }
    }
  }
}

fn join_lobby_effect(
  player_id: String,
  lobby_id: String,
  lobbies: dict.Dict(String, Started(Subject(LobbyMsg))),
) {
  use _dispatch <- effect.from
  let assert Ok(lobby) = dict.get(lobbies, lobby_id)
  lobby.join_lobby(lobby.data, player_id, lobby_id)
  Nil
}

fn leave_lobby_effect(
  player_id: String,
  lobby_id: String,
  lobbies: dict.Dict(String, Started(Subject(LobbyMsg))),
) {
  use _dispatch <- effect.from
  let assert Ok(lobby) = dict.get(lobbies, lobby_id)
  lobby.leave_lobby(lobby.data, player_id)
  Nil
}

fn player_ready_effect(
  player_id: String,
  lobby_id: String,
  lobbies: dict.Dict(String, Started(Subject(LobbyMsg))),
) {
  use _dispatch <- effect.from
  let assert Ok(lobby) = dict.get(lobbies, lobby_id)
  lobby.player_ready(lobby.data, player_id)
  Nil
}

fn player_not_ready_effect(
  player_id: String,
  topic: Topic(AppSharedMsg(LobbyMsg)),
) {
  use _dispatch <- effect.from
  let assert Ok(_) =
    glubsub.broadcast(topic, LobbySharedMsg(PlayerBecameNotReady(player_id)))
  Nil
}

fn close_lobby_effect(
  lobby_id: String,
  lobbies: dict.Dict(String, Started(Subject(LobbyMsg))),
) {
  use _dispatch <- effect.from
  let assert Ok(lobby) = dict.get(lobbies, lobby_id)
  lobby.close_lobby(lobby.data)
  Nil
}

fn view(model: AppModel) -> Element(AppMsg) {
  let body = case model.state {
    InLobby -> view_lobby(model)
    InGame -> view_game(model)
  }
  html.html([attribute.lang("en")], [
    html.head([], [
      html.meta([attribute.charset("utf-8")]),
      html.meta([
        attribute.name("viewport"),
        attribute.content("width=device-width, initial-scale=1"),
      ]),
      html.title([], "Glurve Fever"),
      html.link([
        attribute.rel("stylesheet"),
        attribute.href("/static/lobby.css"),
      ]),
      html.link([
        attribute.rel("stylesheet"),
        attribute.href("/static/game.css"),
      ]),
    ]),
    html.body([], [body]),
  ])
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
                event.on_click(LobbyMsg(JoinLobby(model.player_id, lobby_id))),
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
      html.link([
        attribute.rel("stylesheet"),
        attribute.href("/static/game.css"),
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
            html.div([attribute.class("form-group")], [
              html.label([attribute.for("lobby-name")], [
                html.text("Lobby Name"),
              ]),
              view_lobby_name_input(create_lobby),
            ]),
          ]),
          html.div([attribute.class("section")], [
            html.h2([], [html.text("Current Lobby")]),
            html.div([attribute.id("current-lobby-info")], [
              case current_lobby {
                Some(lobby_info) -> {
                  html.div([attribute.class("lobby-item current-lobby")], [
                    html.div([attribute.class("lobby-info")], [
                      html.h3([], [
                        html.text("🎯 Current Lobby: " <> lobby_info.name),
                      ]),
                      html.p([], [
                        html.text(
                          "Ready players: "
                          <> int.to_string(set.size(lobby_info.ready_players))
                          <> "/"
                          <> int.to_string(set.size(lobby_info.players))
                          <> " • Status: "
                          <> lobby.status_to_string(lobby_info.status),
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
                      [html.text("Leave")],
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
    Some(lobby_info) ->
      html.div([attribute.class("game-container")], [
        html.header([attribute.class("game-header")], [
          html.h1([], [html.text("🎮 Glurve Fever — " <> lobby_info.name)]),
          html.button(
            [
              attribute.class("btn btn-exit"),
              event.on_click(LobbyMsg(LeaveLobby(model.player_id))),
            ],
            [html.text("Exit to Lobby")],
          ),
        ]),
        html.main([attribute.class("game-canvas-wrapper")], [
          server_component.element(
            [server_component.route("/ws/" <> lobby_info.name)],
            [],
          ),
        ]),
        html.footer([attribute.class("game-footer")], [
          html.p([], [
            html.text(
              "Players: " <> int.to_string(set.size(lobby_info.players)),
            ),
          ]),
        ]),
      ])
    None ->
      html.div([attribute.class("game-empty")], [html.text("No game selected.")])
  }
}
