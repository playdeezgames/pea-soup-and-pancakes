# Pea Soup and Pancakes

Chess crossed with Snake. You are a stack of pancakes on a chessboard tablecloth. Your head moves like the last pea-soup chess piece you ate, your body trails behind you, and the soup fights back one piece at a time. Eat the soup king to clear the bowl. It's Thursday.

Play it: https://playdeezgames.github.io/pea-soup-and-pancakes/

Rules: [DESIGN.md](DESIGN.md).

## Controls

- Mouse or touch: tap a dotted square (or a gold-boxed pea) to move there.
- Keyboard: arrows or WASD move the cursor, Enter or Space moves there.
- Gamepad: d-pad or left stick, A or Start.

## Build

Needs Odin (`dev-2026-11` here) and Python 3 for a local server.

```bash
tools/test.sh      # native rules tests plus a wasm type check
tools/build.sh     # builds build/web (--size for the shipping build)
python3 -m http.server -d build/web 8047
```

`?demo` opens a fixed mid-game scene for screenshots.

## Credits

Pea Soup and Pancakes by TheGrumpyGameDev. Font m5x7 by Daniel Linssen (CC0). Code, piece art and sound were made by an AI agent (Claude Code) at the author's direction.
