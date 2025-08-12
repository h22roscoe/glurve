# glurve

## This is a Gleam implementation of [Curve Fever](https://en.wikipedia.org/wiki/Achtung,_die_Kurve!)

[![Package Version](https://img.shields.io/hexpm/v/glurve)](https://hex.pm/packages/glurve)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/glurve/)

## Development

```sh
gleam run   # Run the game
gleam test  # Run the tests
```

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
- [ ] Player status should be in game while in game
- [ ] Think of ways to add tests
- [ ] (Longer term) Multiple rounds in a game
- [ ] (Longer term) Points per round and scoreboard display
- [ ] (Longer term) Join as spectator