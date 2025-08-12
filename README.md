# glurve

## This is a Gleam implementation of [Curve Fever](https://en.wikipedia.org/wiki/Achtung,_die_Kurve!)

[![Package Version](https://img.shields.io/hexpm/v/glurve)](https://hex.pm/packages/glurve)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glurve/)

## Development

```sh
gleam run   # Run the game
gleam test  # Run the tests
```

## Deployment

For now I am roughly following [this guide](https://gleam.run/deployment/fly/) except I am using [nixpacks](https://nixpacks.com/docs/providers/gleam) to build a docker image

I needed to update the way nixpacks installs a gleam version which I did in [this PR](https://github.com/railwayapp/nixpacks/pull/1352) so for now locally from that fork I run:

```sh
cargo run -- build ../glurve --name glurve --out ../glurve
```
which should become just:
```sh
nixpacks build . --name glurve
```
and deploying is currently:
```sh
flyctl launch --dockerfile .nixpacks/Dockerfile
```
but specifying the Dockerfile location might be superfluous after the PR is in since I will put it at the top level instead.

## Features needed
- [x] Join lobby when you create it
- [x] Add ability for game to communicate back to app when done, which closes the lobby and transitions players to lobby screen
- [x] Add style to game screen
- [x] Ability to unready yourself in a lobby
- [x] Add resizing game screen capability (based on num players mostly)
- [ ] Player should be able to change their name
- [x] Player should be able to choose their colour
- [x] Colour should translate to game colour
- [x] Player status should reset to not ready on refresh
- [x] Player status should be in game while in game
- [x] Deploy somewhere
- [ ] Colorful tail circles improved
- [ ] Room search
- [ ] Host can kick players
- [ ] (Longer term) Regional rooms
- [ ] Join by code functionality
- [ ] Private rooms
- [ ] Think of ways to add tests
- [ ] More diverse start positions
- [ ] Highlighting of player during countdown
- [ ] Clean up of rooms that are >1 day old
- [ ] (Longer term) Multiple rounds in a game
- [ ] (Longer term) Points per round and scoreboard display
- [ ] (Longer term) Power ups in game
- [ ] (Longer term) Join as spectator