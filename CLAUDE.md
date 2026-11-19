# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Pea Soup and Pancakes** is a browser game (chess crossed with Snake), written in Odin and compiled to `js_wasm32`. The rules are in `DESIGN.md`; all of them are the user's decisions (November 19, 2026). Record any new rule there with the date, and mark it provisional until the user confirms it. Started November 19, 2026.

## Layout

- `game/`: all rules and state (moves for both sides, the soup AI, turn flow, input, a sound queue). No JS, no `core:os`. `game_test.odin` is `#+build !js`.
- `src/web/main.odin` (`#+build js`): drawing and input routing only. It imports `psp:game` through `-collection:psp=.`.
- `web/index.html`: the canvas shim (12×12 piece masks in `PIECES`, indexed like `game.Kind`; drawn pancakes and syrup; m5x7 bitmap text; Web Audio blips in `SOUNDS`, ordered like `game.Sound`; keyboard and gamepad mapped to `game.Action` through `ACTION`), plus the footer back links and the hidden LootLocker feedback link (no LootLocker game yet; the user's call).

## Build and run

```bash
tools/test.sh       # native tests and a wasm check of src/web
tools/build.sh      # build/web; --size for shipping
python3 -m http.server -d build/web 8047
```

`?demo` calls the `qa_demo` export (a fixed mid-game scene). In the browser pane, space out taps with waits between tool calls: the pane does not run frames while a script is busy.

## External resources

- **Vault:** `/home/yermom/git/bok-of-splorr/splorr` (read `Home.md` first for the standing rules, then `Tech/Odin wasm recipe.md`, `Tech/Release standard.md`, `Gotchas.md`). This game's note is `Games/Pea Soup and Pancakes.md`.

## Release and safety rules (from the vault's `Home.md`)

- Never `git push` or ship unless the user says so ("push" means `git push`; "ship" means itch.io).
- GitHub Pages: the repo is public (https://github.com/playdeezgames/pea-soup-and-pancakes) and Pages serves `main` `/docs` at https://playdeezgames.github.io/pea-soup-and-pancakes/ (since November 19, 2026). To update it, run `tools/pages.sh`, commit `docs/`, and push only when the user says push.
- itch.io material (`ITCH_DESCRIPTION.md`, cover, screenshots, `tools/ship.sh`, `shippit.sh`) is made only when the user decides the game goes to itch.io. On itch it is a "Metaphor", ships go through Coxswain, and anything an AI agent posts there says so.
