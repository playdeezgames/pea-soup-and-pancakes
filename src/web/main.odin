// Thin browser layer: input, drawing and the frame loop. Rules and state live in package game.
#+build js
package main

import "base:runtime"
import "core:time"
import "psp:game"

foreign import canvas "canvas"
@(default_calling_convention = "contextless")
foreign canvas {
	// rgb is 0xRRGGBB; coordinates are logical pixels, y down.
	fill_rect :: proc(x, y, w, h: f32, rgb: u32, alpha: f32) ---
	// A chess piece silhouette (game.Kind) in a 16x16 tile at x, y, filled with rgb and outlined with edge.
	piece :: proc(kind: i32, x, y: f32, rgb, edge: u32) ---
	// A pancake seen from the side, centred in the tile at x, y. head draws it bigger with a butter pat.
	pancake :: proc(x, y: f32, head: bool) ---
	// A syrup line between two points.
	line :: proc(x0, y0, x1, y1: f32, rgb: u32, width, alpha: f32) ---
	play_sound :: proc(sound: i32) ---
	// Bitmap text (m5x7). y is the baseline; scale is a whole number; x is the centre when centered.
	draw_text :: proc(x, y: f32, text: string, rgb: u32, scale: i32, centered: bool) ---
	load_best :: proc() -> i32 ---
	save_best :: proc(score: i32) ---
}

WHITE :: 0xfff8e8
DIM :: 0xb8a888
GOLD :: 0xf5c542
RED :: 0xd8433a
BACKDROP :: 0x2b1d14
CLOTH_A :: 0xf4ecd8
CLOTH_B :: 0xc8d8e8
PEA :: 0x86b84a
PEA_EDGE :: 0x2c4a16
SYRUP :: 0x7a3e12

ctx: runtime.Context
state: game.Game

main :: proc() {
	ctx = context
	state = game.title(u64(time.now()._nsec))
	state.best = int(load_best())
}

@(export)
click :: proc "c" (x, y: i32) {
	context = ctx
	game.click(&state, int(x), int(y))
}

@(export)
input :: proc "c" (action: i32) {
	context = ctx
	game.input(&state, game.Action(action))
}

// QA: a fixed mid-game scene (a long stack, a rook-moving head) for screenshots. index.html calls it for ?demo.
@(export)
qa_demo :: proc "c" () {
	context = ctx
	game.demo(&state)
}

@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {
	context = ctx
	game.update(&state, f32(dt))
	if state.save_best {
		save_best(i32(state.best))
		state.save_best = false
	}
	for {
		s, ok := game.take_sound(&state)
		if !ok {break}
		play_sound(i32(s))
	}
	draw()
	return true
}

tile_x :: proc(x: int) -> f32 {return f32(game.BOARD_X + x * game.TILE)}
tile_y :: proc(y: int) -> f32 {return f32(game.BOARD_Y + y * game.TILE)}

draw_board :: proc(g: ^game.Game) {
	threat := game.threats(g)
	moves: game.Moves
	my_turn := game.can_move(g)
	if my_turn {moves = game.player_moves(g)}

	for y in 0 ..< game.SIZE {
		for x in 0 ..< game.SIZE {
			px, py := tile_x(x), tile_y(y)
			fill_rect(px, py, game.TILE, game.TILE, (x + y) % 2 == 0 ? CLOTH_A : CLOTH_B, 1)
			if g.phase == .Playing && threat[y][x] {
				fill_rect(px, py, game.TILE, game.TILE, RED, 0.22)
			}
		}
	}
	if g.has_last && g.phase != .Title {
		for p in ([2]game.Pos{g.last_from, g.last_to}) {
			fill_rect(tile_x(p.x), tile_y(p.y), game.TILE, game.TILE, PEA, 0.3)
		}
	}

	// Syrup drizzle joining the stack in order, head first.
	for i in 1 ..< g.length {
		a, b := g.segs[i - 1], g.segs[i]
		line(tile_x(a.x) + 8, tile_y(a.y) + 8, tile_x(b.x) + 8, tile_y(b.y) + 8, SYRUP, 2, 0.55)
	}
	for i := g.length - 1; i >= 1; i -= 1 {
		p := g.segs[i]
		pancake(tile_x(p.x), tile_y(p.y), false)
	}

	for y in 0 ..< game.SIZE {
		for x in 0 ..< game.SIZE {
			if k := g.soup[y][x]; k != .None {
				piece(i32(k), tile_x(x), tile_y(y), PEA, k == .King ? GOLD : PEA_EDGE) // the soup king wears gold
			}
		}
	}

	if h := g.segs[0]; g.phase != .Title && g.soup[h.y][h.x] == .None { // not when a pea has just eaten it
		pancake(tile_x(h.x), tile_y(h.y), true)
		piece(i32(g.head_kind), tile_x(h.x), tile_y(h.y) - 3, SYRUP, 0xf0c070)
	}

	if my_turn {
		for i in 0 ..< moves.n {
			p := moves.to[i]
			cx, cy := tile_x(p.x), tile_y(p.y)
			if g.soup[p.y][p.x] != .None {
				box(cx, cy, GOLD)
			} else {
				fill_rect(cx + 6, cy + 6, 4, 4, SYRUP, 0.6)
			}
		}
	}

	if g.cursor_on && g.phase == .Playing {
		box(tile_x(g.cursor.x), tile_y(g.cursor.y), 0x2050c0)
	}
}

box :: proc(x, y: f32, rgb: u32) {
	t :: f32(game.TILE)
	fill_rect(x, y, t, 1, rgb, 1)
	fill_rect(x, y + t - 1, t, 1, rgb, 1)
	fill_rect(x, y, 1, t, rgb, 1)
	fill_rect(x + t - 1, y, 1, t, rgb, 1)
}

draw :: proc() {
	g := &state
	fill_rect(0, 0, game.LOGICAL_W, game.LOGICAL_H, BACKDROP, 1)
	draw_board(g)
	cx :: f32(game.LOGICAL_W / 2)

	switch g.phase {
	case .Title:
		fill_rect(0, 0, game.LOGICAL_W, game.LOGICAL_H, 0x000000, 0.62)
		draw_text(cx, 44, "PEA SOUP", PEA, 2, true)
		draw_text(cx, 62, "& PANCAKES", GOLD, 2, true)
		draw_text(cx, 80, "It's Thursday.", WHITE, 1, true)
		draw_text(cx, 98, "You are a stack of pancakes.", DIM, 1, true)
		draw_text(cx, 108, "Eat a pea piece: move like it.", DIM, 1, true)
		draw_text(cx, 118, "Eat the soup king: next bowl.", DIM, 1, true)
		draw_text(cx, 128, "Red squares can bite you.", DIM, 1, true)
		draw_text(cx, 148, "tap or Enter to start", GOLD, 1, true)
		if g.best > 0 {
			buf: [32]u8
			draw_text(cx, 164, join(&buf, "best: ", g.best), DIM, 1, true)
		}
	case .Playing, .Over:
		b1, b2, b3: [32]u8
		draw_text(4, 10, join(&b1, "BOWL ", g.level), WHITE, 1, false)
		draw_text(cx, 10, join(&b2, "SCORE ", g.score), GOLD, 1, true)
		stack := g.length + g.grow
		draw_text(140 - 36, 10, join(&b3, "STACK ", stack), WHITE, 1, false)
		msg: string
		colour: u32 = WHITE
		mb: [48]u8
		if g.phase == .Over {
			fill_rect(0, 60, game.LOGICAL_W, 52, 0x000000, 0.7)
			why := g.outcome == .Eaten ? "EATEN BY THE SOUP" : "YOUR STACK WENT COLD"
			draw_text(cx, 78, why, RED, 1, true)
			sb: [32]u8
			draw_text(cx, 92, join(&sb, "score ", g.score), GOLD, 1, true)
			if g.new_best {
				draw_text(cx, 104, "NEW BEST!", GOLD, 1, true)
			} else {
				bb: [32]u8
				draw_text(cx, 104, join(&bb, "best ", g.best), DIM, 1, true)
			}
			msg = "tap to play again"
			colour = GOLD
		} else if g.note != "" {
			msg = g.note
			colour = GOLD
		} else if game.can_move(g) {
			n := copy(mb[:], "you move as a ")
			n += copy(mb[n:], game.kind_name(g.head_kind))
			msg = string(mb[:n])
		} else {
			msg = "the soup is stirring..."
			colour = DIM
		}
		draw_text(cx, 168, msg, colour, 1, true)
	}
}

// prefix followed by a decimal number, written into buf.
join :: proc(buf: ^[32]u8, prefix: string, n: int) -> string {
	k := copy(buf[:], prefix)
	digits: [16]u8
	i := len(digits)
	v := n
	if v == 0 {
		i -= 1
		digits[i] = '0'
	}
	for v > 0 && i > 0 {
		i -= 1
		digits[i] = u8('0' + v % 10)
		v /= 10
	}
	k += copy(buf[k:], digits[i:])
	return string(buf[:k])
}
