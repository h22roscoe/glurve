import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/otp/actor.{type Started}
import gleam/pair
import gleam/result
import gleam/set
import gleam/string
import gleam_community/colour
import glubsub.{type Topic}
import lobby/lobby.{
  type LobbyInfo, type LobbyMsg, CloseLobby, GetGameTopic, GetLobbyInfo,
  JoinLobby, LeaveLobby, LobbyInfo, PlayerNotReady, PlayerReady,
}
import lobby/lobby_manager.{
  type LobbyManagerMsg, CreateLobby, ListLobbies, RemoveLobby, SearchLobbies,
  UpdateLobbyMap, UpdateLobbyMaxPlayers, UpdateLobbyMode, UpdateLobbyName,
  UpdateLobbyRegion,
}
import lustre.{type App}
import lustre/attribute
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg
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
    player: lobby.Player,
    lobbies: dict.Dict(String, Started(Subject(lobby.LobbyMsg))),
    current_lobby: Option(LobbyInfo),
    lobby_manager: Started(Subject(LobbyManagerMsg)),
    topic: Topic(AppSharedMsg(LobbyMsg)),
    pending_created_lobby: Option(String),
    lobby_search_input: Option(String),
    lobby_name_input: Option(String),
    lobby_max_players_input: Option(Int),
    lobby_map_input: Option(String),
    lobby_mode_input: Option(String),
    lobby_region_input: Option(String),
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
  let lobbies = lobby_manager.list_lobbies(args.lobby_manager.data)
  let player_with_info =
    dict.to_list(lobbies)
    |> list.map(fn(pair) {
      let #(_lobby_name, l) = pair
      let info = lobby.get_lobby_info(l.data)
      let player =
        info.players
        |> set.to_list()
        |> list.find(fn(p) { p.id == args.user_id })
      case player {
        Ok(player) -> Ok(#(player, info))
        Error(_) -> Error(Nil)
      }
    })
    |> list.reduce(fn(acc, pair) {
      case pair {
        Ok(pair) -> Ok(pair)
        Error(_) -> acc
      }
    })
    |> result.flatten()

  let player = case player_with_info {
    Ok(#(player, _info)) -> player
    Error(_) ->
      lobby.Player(
        id: args.user_id,
        name: "Anonymous player",
        colour: colour.red,
        status: lobby.NotReady,
      )
  }

  let info = case player_with_info {
    Ok(#(_, info)) -> Some(info)
    Error(_) -> None
  }

  let model =
    AppModel(
      state: InLobby,
      player: player,
      lobbies: lobbies,
      current_lobby: info,
      lobby_manager: args.lobby_manager,
      topic: args.topic,
      pending_created_lobby: None,
      lobby_search_input: None,
      lobby_name_input: None,
      lobby_max_players_input: None,
      lobby_map_input: None,
      lobby_mode_input: None,
      lobby_region_input: None,
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
      let updated_lobbies = dict.insert(model.lobbies, lobby_id, lobby)
      case model.pending_created_lobby {
        Some(pending) if pending == lobby_id -> #(
          AppModel(
            ..model,
            lobbies: updated_lobbies,
            pending_created_lobby: None,
          ),
          join_lobby_effect(model.player, lobby_id, updated_lobbies),
        )
        _ -> #(AppModel(..model, lobbies: updated_lobbies), effect.none())
      }
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
        LobbyJoined(player_id, lobby_id) if player_id == model.player.id -> {
          let assert Ok(lobby) = dict.get(model.lobbies, lobby_id)
          let lobby_info = lobby.get_lobby_info(lobby.data)
          #(AppModel(..model, current_lobby: Some(lobby_info)), effect.none())
        }
        _ -> #(model, effect.none())
      }
    }
    Some(lobby_info) -> {
      case msg {
        LobbyJoined(_player_id, lobby_id) if lobby_id == lobby_info.name -> {
          // A player joined the lobby we are in so refresh the lobby info from source
          let assert Ok(lobby) = dict.get(model.lobbies, lobby_id)
          let lobby_info = lobby.get_lobby_info(lobby.data)
          #(AppModel(..model, current_lobby: Some(lobby_info)), effect.none())
        }
        LobbyJoined(_, _) -> {
          #(model, effect.none())
        }
        LobbyLeft(player_id) -> {
          case player_id == model.player.id {
            True -> #(
              AppModel(..model, current_lobby: None, state: InLobby),
              effect.none(),
            )

            False -> {
              let assert Ok(player) =
                list.find(set.to_list(lobby_info.players), fn(player) {
                  player.id == player_id
                })
              let lobby_info =
                LobbyInfo(
                  ..lobby_info,
                  players: set.delete(lobby_info.players, player),
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
              players: set.map(lobby_info.players, fn(p) {
                case p.id == player_id {
                  True -> lobby.Player(..p, status: lobby.Ready)
                  False -> p
                }
              }),
            )
          #(AppModel(..model, current_lobby: Some(lobby_info)), effect.none())
        }
        PlayerBecameNotReady(player_id) -> {
          let lobby_info =
            LobbyInfo(
              ..lobby_info,
              players: set.map(lobby_info.players, fn(p) {
                case p.id == player_id {
                  True -> lobby.Player(..p, status: lobby.NotReady)
                  False -> p
                }
              }),
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
    CreateLobby(name, host_id, max_players, map, mode, region) -> {
      #(
        AppModel(..model, pending_created_lobby: Some(name)),
        create_lobby_effect(
          lobby_manager,
          name,
          host_id,
          max_players,
          map,
          mode,
          region,
        ),
      )
    }
    RemoveLobby(lobby_id) -> {
      #(model, remove_lobby_effect(lobby_manager, lobby_id))
    }
    ListLobbies(_) -> {
      let lobbies = lobby_manager.list_lobbies(lobby_manager.data)
      #(AppModel(..model, lobbies: lobbies), effect.none())
    }
    SearchLobbies(search) -> {
      let lobbies = lobby_manager.list_lobbies(lobby_manager.data)
      #(
        AppModel(
          ..model,
          lobbies: dict.filter(lobbies, fn(name, _lobby) {
            name |> string.contains(search)
          }),
        ),
        effect.none(),
      )
    }
    UpdateLobbyName(name) -> {
      #(AppModel(..model, lobby_name_input: Some(name)), effect.none())
    }
    UpdateLobbyMaxPlayers(max_players) -> {
      #(
        AppModel(..model, lobby_max_players_input: Some(max_players)),
        effect.none(),
      )
    }
    UpdateLobbyMap(map) -> {
      #(AppModel(..model, lobby_map_input: Some(map)), effect.none())
    }
    UpdateLobbyMode(mode) -> {
      #(AppModel(..model, lobby_mode_input: Some(mode)), effect.none())
    }
    UpdateLobbyRegion(region) -> {
      #(AppModel(..model, lobby_region_input: Some(region)), effect.none())
    }
  }
}

fn create_lobby_effect(
  lobby_manager: Started(Subject(LobbyManagerMsg)),
  name: String,
  host_id: String,
  max_players: Int,
  map: String,
  mode: String,
  region: String,
) {
  use _dispatch <- effect.from
  lobby_manager.create_lobby(
    lobby_manager.data,
    name,
    host_id,
    max_players,
    map,
    mode,
    region,
  )
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
    JoinLobby(player, lobby_id) -> {
      #(model, join_lobby_effect(player, lobby_id, model.lobbies))
    }
    LeaveLobby(player) -> {
      case model.current_lobby {
        Some(lobby_info) -> {
          let is_host = lobby_info.host_id == player.id
          case is_host {
            True -> #(
              model,
              effect.batch([
                leave_lobby_effect(player, lobby_info.name, model.lobbies),
                close_lobby_effect(lobby_info.name, model.lobbies),
                remove_lobby_effect(model.lobby_manager, lobby_info.name),
              ]),
            )
            False -> #(
              model,
              leave_lobby_effect(player, lobby_info.name, model.lobbies),
            )
          }
        }
        None -> #(model, effect.none())
      }
    }
    PlayerReady(player) -> {
      case model.current_lobby {
        Some(lobby_info) -> {
          #(model, player_ready_effect(player, lobby_info.name, model.lobbies))
        }
        None -> #(model, effect.none())
      }
    }
    PlayerNotReady(player) -> {
      #(model, player_not_ready_effect(player, model.topic))
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
  player: lobby.Player,
  lobby_id: String,
  lobbies: dict.Dict(String, Started(Subject(LobbyMsg))),
) {
  use _dispatch <- effect.from
  let assert Ok(lobby) = dict.get(lobbies, lobby_id)
  lobby.join_lobby(lobby.data, player, lobby_id)
  Nil
}

fn leave_lobby_effect(
  player: lobby.Player,
  lobby_id: String,
  lobbies: dict.Dict(String, Started(Subject(LobbyMsg))),
) {
  use _dispatch <- effect.from
  let assert Ok(lobby) = dict.get(lobbies, lobby_id)
  lobby.leave_lobby(lobby.data, player)
  Nil
}

fn player_ready_effect(
  player: lobby.Player,
  lobby_id: String,
  lobbies: dict.Dict(String, Started(Subject(LobbyMsg))),
) {
  use _dispatch <- effect.from
  let assert Ok(lobby) = dict.get(lobbies, lobby_id)
  lobby.player_ready(lobby.data, player)
  Nil
}

fn player_not_ready_effect(
  player: lobby.Player,
  topic: Topic(AppSharedMsg(LobbyMsg)),
) {
  use _dispatch <- effect.from
  let assert Ok(_) =
    glubsub.broadcast(topic, LobbySharedMsg(PlayerBecameNotReady(player.id)))
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
  case model.state {
    InLobby -> view_lobby(model)
    InGame -> view_game(model)
  }
}

fn view_lobby(model: AppModel) -> Element(AppMsg) {
  html.div([attribute.id("lobby"), attribute.class("screen")], [
    view_lobby_list(model),
    view_create_join_form(model),
    view_lobby_players(model),
  ])
}

fn update_lobby_name(name: String) -> AppMsg {
  LobbyManagerMsg(UpdateLobbyName(name))
}

fn update_lobby_max_players(max_players: String) -> AppMsg {
  LobbyManagerMsg(UpdateLobbyMaxPlayers(
    int.base_parse(max_players, 10) |> result.unwrap(4),
  ))
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
              event.on_click(LobbyMsg(LeaveLobby(model.player))),
            ],
            [html.text("Exit to Lobby")],
          ),
        ]),
        html.main([attribute.class("game-canvas-wrapper")], [
          html.div(
            [
              attribute.class("game-wrapper"),
              // Scales with viewport, capped for large screens
              attribute.style("width", "min(80vmin, 820px)"),
              attribute.style("height", "min(80vmin, 820px)"),
            ],
            [
              server_component.element(
                [server_component.route("/ws/" <> lobby_info.name)],
                [],
              ),
            ],
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

fn view_lobby_list(model: AppModel) -> Element(AppMsg) {
  let lobbies_list = case dict.size(model.lobbies) {
    0 -> [
      html.div([attribute.class("empty-state")], [
        html.div([attribute.class("empty-state-icon")], [html.text("🕳️")]),
        html.div([attribute.class("empty-state-title")], [
          html.text("No rooms found"),
        ]),
        html.div([attribute.class("empty-state-text")], [
          html.text("Be the first to create a room!"),
        ]),
      ]),
    ]
    _ ->
      {
        use lobby_id, lobby <- dict.map_values(model.lobbies)
        let lobby_state = lobby.get_lobby_info(lobby.data)
        html.div([attribute.class("item")], [
          html.div([], [
            html.h3([], [
              html.text(lobby_id),
            ]),
            html.div([attribute.class("meta")], [
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
          html.div(
            [
              attribute.style("display", "flex"),
              attribute.style("gap", "6px"),
              attribute.style("align-items", "center"),
            ],
            [
              html.span([attribute.class("pill")], [html.text("EU")]),
              html.button(
                [
                  attribute.class("btn"),
                  event.on_click(LobbyMsg(JoinLobby(model.player, lobby_id))),
                ],
                [
                  svg.svg(
                    [
                      attribute.class("lobby-button-icon"),
                      attribute.attribute("viewBox", "0 0 640 512"),
                      attribute.attribute("fill", "#ffaff3"),
                    ],
                    [
                      svg.path([
                        attribute.attribute(
                          "d",
                          "M136 128a120 120 0 1 1 240 0 120 120 0 1 1 -240 0zM48 482.3C48 383.8 127.8 304 226.3 304l59.4 0c98.5 0 178.3 79.8 178.3 178.3 0 16.4-13.3 29.7-29.7 29.7L77.7 512C61.3 512 48 498.7 48 482.3zM544 96c13.3 0 24 10.7 24 24l0 48 48 0c13.3 0 24 10.7 24 24s-10.7 24-24 24l-48 0 0 48c0 13.3-10.7 24-24 24s-24-10.7-24-24l0-48-48 0c-13.3 0-24-10.7-24-24s10.7-24 24-24l48 0 0-48c0-13.3 10.7-24 24-24z",
                        ),
                      ]),
                    ],
                  ),
                  html.text("Join"),
                ],
              ),
            ],
          ),
        ])
      }
      |> dict.to_list
      |> list.map(pair.second)
  }

  html.div([attribute.class("panel")], [
    html.div(
      [attribute.class("toolbar"), attribute.style("margin-bottom", "10px")],
      [
        html.input([
          attribute.class("search"),
          attribute.placeholder("Search rooms…"),
          attribute.value(model.lobby_search_input |> option.unwrap("")),
        ]),
        html.button([attribute.class("btn btn--ghost")], [
          html.text("Refresh"),
        ]),
      ],
    ),
    html.div(
      [
        attribute.class("list"),
        attribute.attribute("aria-label", "Room list"),
      ],
      lobbies_list,
    ),
  ])
}

fn view_create_join_form(model: AppModel) -> Element(AppMsg) {
  html.div(
    [
      attribute.class("panel"),
      attribute.class("room-form"),
    ],
    [
      // Room name row
      html.div(
        [
          attribute.class("row"),
          attribute.style("grid-template-columns", "1fr"),
        ],
        [
          html.div([attribute.class("field")], [
            html.label([attribute.for("room-name")], [html.text("Room name")]),
            html.input([
              attribute.id("room-name"),
              attribute.placeholder("e.g., Harry's Room"),
              attribute.type_("text"),
              attribute.required(True),
              attribute.value(model.lobby_name_input |> option.unwrap("")),
              event.on_input(update_lobby_name),
            ]),
          ]),
        ],
      ),
      // Region and Mode row
      html.div([attribute.class("row"), attribute.style("margin-top", "8px")], [
        html.div([attribute.class("field")], [
          html.label([attribute.for("region")], [html.text("Region")]),
          html.select([attribute.id("region")], [
            html.option([], "EU"),
            html.option([], "US"),
            html.option([], "AS"),
          ]),
        ]),
        html.div([attribute.class("field")], [
          html.label([attribute.for("mode")], [html.text("Mode")]),
          html.select([attribute.id("mode")], [
            html.option([], "Points"),
            html.option([], "Last Stand"),
          ]),
        ]),
      ]),
      // Max players and Map row
      html.div([attribute.class("row"), attribute.style("margin-top", "8px")], [
        html.div([attribute.class("field")], [
          html.label([attribute.for("max")], [html.text("Max players")]),
          html.select(
            [attribute.id("max"), event.on_change(update_lobby_max_players)],
            [
              html.option(
                [
                  attribute.selected(
                    model.lobby_max_players_input |> option.unwrap(4) == 4,
                  ),
                ],
                "4",
              ),
              html.option(
                [
                  attribute.selected(
                    model.lobby_max_players_input |> option.unwrap(4) == 6,
                  ),
                ],
                "6",
              ),
              html.option(
                [
                  attribute.selected(
                    model.lobby_max_players_input |> option.unwrap(4) == 8,
                  ),
                ],
                "8",
              ),
            ],
          ),
        ]),
        html.div([attribute.class("field")], [
          html.label([attribute.for("map")], [html.text("Map")]),
          html.select([attribute.id("map")], [
            html.option([], "Classic"),
            html.option([], "Tight"),
            html.option([], "Wide"),
          ]),
        ]),
      ]),
      // Toolbar row
      html.div(
        [
          attribute.class("toolbar"),
          attribute.style("margin-top", "12px"),
          attribute.style("justify-content", "flex-end"),
        ],
        [
          html.button([attribute.class("btn"), attribute.class("btn--ghost")], [
            html.text("Join by Code"),
          ]),
          html.button(
            [
              attribute.class("btn"),
              event.on_click(
                LobbyManagerMsg(CreateLobby(
                  model.lobby_name_input |> option.unwrap(""),
                  model.player.id,
                  model.lobby_max_players_input |> option.unwrap(4),
                  model.lobby_map_input |> option.unwrap(""),
                  model.lobby_mode_input |> option.unwrap(""),
                  model.lobby_region_input |> option.unwrap(""),
                )),
              ),
            ],
            [html.text("Create Room")],
          ),
        ],
      ),
    ],
  )
}

fn view_lobby_players(model: AppModel) -> Element(AppMsg) {
  let content = case model.current_lobby {
    None ->
      html.div([attribute.class("empty-state")], [
        html.div([attribute.class("empty-state-icon")], [html.text("🚪")]),
        html.div([attribute.class("empty-state-title")], [
          html.text("No room selected"),
        ]),
        html.div([attribute.class("empty-state-text")], [
          html.text("Select a room to see players"),
        ]),
      ])
    Some(lobby_info) -> {
      let players = set.to_list(lobby_info.players)
      let #(hosts, other_players) =
        list.partition(players, fn(player) { player.id == lobby_info.host_id })
      let assert Ok(host) = list.first(hosts)
      let we_are_host = host.id == model.player.id
      let host_elem =
        html.div([attribute.class("player")], [
          html.div([attribute.class("avatar")], [html.text("🟢")]),
          html.div([], [
            html.div([attribute.style("font-weight", "700")], [
              html.text(host.name),
            ]),
            html.div([attribute.class("meta")], [
              html.text(lobby.player_status_to_string(host.status)),
            ]),
          ]),
          html.div([attribute.class("player-actions")], [
            html.span([attribute.class("pill")], [html.text("Host")]),
            case we_are_host {
              True ->
                element.fragment([
                  html.button(
                    [
                      attribute.class("btn"),
                      attribute.class("btn--ghost"),
                      event.on_click(LobbyMsg(LeaveLobby(model.player))),
                    ],
                    [
                      html.text("Leave"),
                    ],
                  ),
                  html.button(
                    [
                      attribute.class("btn"),
                      event.on_click(LobbyMsg(PlayerReady(model.player))),
                    ],
                    [html.text("Ready")],
                  ),
                ])
              False -> element.none()
            },
          ]),
        ])
      let other_players_list = {
        use player <- list.map(other_players)
        let is_us = player.id == model.player.id

        html.div([attribute.class("player")], [
          html.div([attribute.class("avatar")], [html.text("🟣")]),
          html.div([], [
            html.div([attribute.style("font-weight", "700")], [
              html.text(player.name),
            ]),
            html.div([attribute.class("meta")], [
              html.text(lobby.player_status_to_string(player.status)),
            ]),
          ]),
          case we_are_host {
            True ->
              html.button(
                [attribute.class("btn"), attribute.class("btn--ghost")],
                [
                  html.text("Kick"),
                ],
              )
            False -> element.none()
          },
          case is_us {
            True ->
              html.div([attribute.class("player-actions")], [
                html.span([attribute.class("pill")], [html.text("You")]),
                html.button(
                  [
                    attribute.class("btn"),
                    attribute.class("btn--ghost"),
                    event.on_click(LobbyMsg(LeaveLobby(model.player))),
                  ],
                  [
                    html.text("Leave"),
                  ],
                ),
                html.button(
                  [
                    attribute.class("btn"),
                    event.on_click(LobbyMsg(PlayerReady(model.player))),
                  ],
                  [html.text("Ready")],
                ),
              ])
            False -> element.none()
          },
        ])
      }
      let player_list = [host_elem, ..other_players_list]

      element.fragment([
        html.div(
          [
            attribute.style("display", "flex"),
            attribute.style("align-items", "center"),
            attribute.style("justify-content", "space-between"),
            attribute.style("margin-bottom", "8px"),
          ],
          [
            html.div([attribute.style("font-weight", "800")], [
              html.text("Players"),
            ]),
            html.div([attribute.class("pill")], [
              html.text("Room Code: " <> lobby_info.code),
            ]),
          ],
        ),
        html.div([attribute.class("players")], player_list),
      ])
    }
  }

  html.div([attribute.class("panel")], [content])
}
