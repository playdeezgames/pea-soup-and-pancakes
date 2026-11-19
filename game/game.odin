// Pea Soup and Pancakes: rules and state. No drawing and no JS; the web layer reads this and draws it.
//
// The player is a stack of pancakes on an 8x8 board. The head moves like the chess piece it ate last
// (a king before its first meal). The body fills the squares the head has landed on, in order.
// The pea-soup side's pieces move like chess pieces, one piece per turn, and can cut the stack
// (capture a body segment) or end the game (capture the head). Eating the soup king clears the level.
// Rules are recorded in the vault: splorr/Concepts/Pea Soup and Pancakes.md.
package game

SIZE :: 8
MAX_LEN :: SIZE * SIZE

LOGICAL_W :: 144
LOGICAL_H :: 176
TILE :: 16
BOARD_X :: 8
BOARD_Y :: 24

SOUP_DELAY :: 0.35 // seconds between the player's move and the soup's reply
NOTE_TIME :: 2.0
KING_BONUS :: 10 // points for eating the soup king

Pos :: [2]int // x, y; y = 0 is the soup's home row, y = SIZE-1 the pancakes' end

Kind :: enum u8 {
	None,
	Pawn,
	Knight,
	Bishop,
	Rook,
	Queen,
	King,
}

// Order must match SOUNDS in web/index.html.
Sound :: enum i32 {
	Move,
	Eat,
	Cut,
	Lose,
	Level,
	Spill,
}

// Keyboard and gamepad commands; the page maps keys and buttons to these.
Action :: enum i32 {
	Up,
	Down,
	Left,
	Right,
	Confirm,
}

Phase :: enum {
	Title,
	Playing,
	Over,
}

Outcome :: enum {
	None,
	Eaten, // a soup piece took the head
	Stuck, // the head had no legal move
}

Rng :: struct {
	s: u64,
}

Moves :: struct {
	to: [32]Pos,
	n:  int,
}

Game :: struct {
	phase:      Phase,
	outcome:    Outcome,
	soup:       [SIZE][SIZE]Kind, // [y][x]
	segs:       [MAX_LEN]Pos, // segs[0] is the head, then the trail of landing squares
	length:     int,
	grow:       int, // pancakes still to add, one per move
	head_kind:  Kind,
	level:      int,
	score:      int,
	turn:       int, // soup turns this level, for pea-pawn spills
	rng:        Rng,
	soup_wait:  f32, // > 0: the soup replies when this reaches 0
	cursor:     Pos,
	cursor_on:  bool,
	last_from:  Pos, // the soup's last move, for a highlight
	last_to:    Pos,
	has_last:   bool,
	note:       string,
	note_t:     f32,
	best:       int, // set by the platform
	new_best:   bool,
	save_best:  bool, // the platform should store `best`, then clear this
	sounds:     [16]Sound,
	nsounds:    int,
}

ORTHO := [4]Pos{{1, 0}, {-1, 0}, {0, 1}, {0, -1}}
DIAG := [4]Pos{{1, 1}, {1, -1}, {-1, 1}, {-1, -1}}
KNIGHT := [8]Pos{{1, 2}, {2, 1}, {2, -1}, {1, -2}, {-1, -2}, {-2, -1}, {-2, 1}, {-1, 2}}

// splitmix64: every random choice goes through this, so a seed replays exactly.
next :: proc(r: ^Rng) -> u64 {
	r.s += 0x9E3779B97F4A7C15
	z := r.s
	z = (z ~ (z >> 30)) * 0xBF58476D1CE4E5B9
	z = (z ~ (z >> 27)) * 0x94D049BB133111EB
	return z ~ (z >> 31)
}

below :: proc(r: ^Rng, n: int) -> int {
	if n <= 0 {return 0}
	return int(next(r) % u64(n))
}

// Chess value: how many pancakes a meal adds.
value :: proc(k: Kind) -> int {
	switch k {
	case .Pawn: return 1
	case .Knight, .Bishop: return 3
	case .Rook: return 5
	case .Queen: return 9
	case .King, .None: return 0
	}
	return 0
}

kind_name :: proc(k: Kind) -> string {
	switch k {
	case .Pawn: return "PAWN"
	case .Knight: return "KNIGHT"
	case .Bishop: return "BISHOP"
	case .Rook: return "ROOK"
	case .Queen: return "QUEEN"
	case .King: return "KING"
	case .None: return ""
	}
	return ""
}

in_board :: proc(p: Pos) -> bool {
	return p.x >= 0 && p.x < SIZE && p.y >= 0 && p.y < SIZE
}

soup_at :: proc(g: ^Game, p: Pos) -> Kind {
	return g.soup[p.y][p.x]
}

// Index of the pancake on p (0 = head), or -1.
pancake_at :: proc(g: ^Game, p: Pos) -> int {
	for i in 0 ..< g.length {
		if g.segs[i] == p {return i}
	}
	return -1
}

add :: proc(m: ^Moves, p: Pos) {
	if m.n < len(m.to) {
		m.to[m.n] = p
		m.n += 1
	}
}

has :: proc(m: ^Moves, p: Pos) -> bool {
	for i in 0 ..< m.n {
		if m.to[i] == p {return true}
	}
	return false
}

// --- Player moves -----------------------------------------------------------------------------

// The head may land on an empty square or a soup piece (eating it). Its own body blocks.
@(private)
player_step :: proc(g: ^Game, m: ^Moves, p: Pos) {
	if in_board(p) && pancake_at(g, p) < 0 {add(m, p)}
}

@(private)
player_slide :: proc(g: ^Game, m: ^Moves, from, d: Pos) {
	p := from + d
	for in_board(p) {
		if pancake_at(g, p) >= 0 {break}
		add(m, p)
		if soup_at(g, p) != .None {break}
		p += d
	}
}

player_moves :: proc(g: ^Game) -> (m: Moves) {
	h := g.segs[0]
	switch g.head_kind {
	case .King, .None:
		for d in ORTHO {player_step(g, &m, h + d)}
		for d in DIAG {player_step(g, &m, h + d)}
	case .Knight:
		for d in KNIGHT {player_step(g, &m, h + d)}
	case .Rook:
		for d in ORTHO {player_slide(g, &m, h, d)}
	case .Bishop:
		for d in DIAG {player_slide(g, &m, h, d)}
	case .Queen:
		for d in ORTHO {player_slide(g, &m, h, d)}
		for d in DIAG {player_slide(g, &m, h, d)}
	case .Pawn:
		// A pancake pawn walks up the board (towards the soup) and eats diagonally forward.
		f := h + {0, -1}
		if in_board(f) && pancake_at(g, f) < 0 && soup_at(g, f) == .None {add(&m, f)}
		for dx in ([2]int{-1, 1}) {
			c := h + {dx, -1}
			if in_board(c) && soup_at(g, c) != .None {add(&m, c)}
		}
	}
	return
}

// --- Soup moves -------------------------------------------------------------------------------

// A soup piece may land on an empty square or a pancake (cutting the stack, or taking the head).
// Other soup pieces block.
@(private)
soup_step :: proc(g: ^Game, m: ^Moves, p: Pos) {
	if in_board(p) && soup_at(g, p) == .None {add(m, p)}
}

@(private)
soup_slide :: proc(g: ^Game, m: ^Moves, from, d: Pos) {
	p := from + d
	for in_board(p) {
		if soup_at(g, p) != .None {break}
		add(m, p)
		if pancake_at(g, p) >= 0 {break}
		p += d
	}
}

soup_moves :: proc(g: ^Game, from: Pos) -> (m: Moves) {
	switch soup_at(g, from) {
	case .None:
	case .King:
		// The soup king never eats pancakes (the user's rule, November 19, 2026), so a stack wrapped
		// round it can trap it.
		for d in ORTHO {
			p := from + d
			if in_board(p) && soup_at(g, p) == .None && pancake_at(g, p) < 0 {add(&m, p)}
		}
		for d in DIAG {
			p := from + d
			if in_board(p) && soup_at(g, p) == .None && pancake_at(g, p) < 0 {add(&m, p)}
		}
	case .Knight:
		for d in KNIGHT {soup_step(g, &m, from + d)}
	case .Rook:
		for d in ORTHO {soup_slide(g, &m, from, d)}
	case .Bishop:
		for d in DIAG {soup_slide(g, &m, from, d)}
	case .Queen:
		for d in ORTHO {soup_slide(g, &m, from, d)}
		for d in DIAG {soup_slide(g, &m, from, d)}
	case .Pawn:
		// Pea-pawns march down the board (towards the pancakes) and capture diagonally forward.
		f := from + {0, 1}
		if in_board(f) && soup_at(g, f) == .None && pancake_at(g, f) < 0 {add(&m, f)}
		for dx in ([2]int{-1, 1}) {
			c := from + {dx, 1}
			if in_board(c) && pancake_at(g, c) >= 0 {add(&m, c)}
		}
	}
	return
}

// Squares a soup piece could take a pancake on next turn (for the threat tint).
threats :: proc(g: ^Game) -> (t: [SIZE][SIZE]bool) {
	for y in 0 ..< SIZE {
		for x in 0 ..< SIZE {
			k := g.soup[y][x]
			if k == .None {continue}
			if k == .Pawn {
				for dx in ([2]int{-1, 1}) {
					c := Pos{x + dx, y + 1}
					if in_board(c) {t[c.y][c.x] = true}
				}
				continue
			}
			m := soup_moves(g, {x, y})
			for i in 0 ..< m.n {t[m.to[i].y][m.to[i].x] = true}
		}
	}
	return
}

// --- Turn flow --------------------------------------------------------------------------------

sound :: proc(g: ^Game, s: Sound) {
	if g.nsounds < len(g.sounds) {
		g.sounds[g.nsounds] = s
		g.nsounds += 1
	}
}

take_sound :: proc(g: ^Game) -> (s: Sound, ok: bool) {
	if g.nsounds == 0 {return}
	s = g.sounds[0]
	for i in 1 ..< g.nsounds {g.sounds[i - 1] = g.sounds[i]}
	g.nsounds -= 1
	return s, true
}

set_note :: proc(g: ^Game, s: string) {
	g.note = s
	g.note_t = NOTE_TIME
}

title :: proc(seed: u64) -> Game {
	g: Game
	g.rng = {seed}
	g.phase = .Title
	return g
}

// A fresh game at level 1. The best score and the RNG carry over.
new_game :: proc(g: ^Game) {
	best, rng := g.best, g.rng
	g^ = {}
	g.best, g.rng = best, rng
	g.phase = .Playing
	g.level = 1
	setup_level(g)
}

// Random empty square in rows y0..y1, away from the pancakes; false if there is none.
@(private)
random_empty :: proc(g: ^Game, y0, y1: int) -> (p: Pos, ok: bool) {
	free: [SIZE * SIZE]Pos
	n := 0
	for y in y0 ..= y1 {
		for x in 0 ..< SIZE {
			q := Pos{x, y}
			if g.soup[y][x] == .None && pancake_at(g, q) < 0 {
				free[n] = q
				n += 1
			}
		}
	}
	if n == 0 {return}
	return free[below(&g.rng, n)], true
}

@(private)
place :: proc(g: ^Game, k: Kind, y0, y1: int) {
	if p, ok := random_empty(g, y0, y1); ok {g.soup[p.y][p.x] = k}
}

// Each level starts with a single king-moving pancake at the bottom and a thicker soup at the top.
setup_level :: proc(g: ^Game) {
	g.soup = {}
	g.length = 1
	g.grow = 0
	g.segs[0] = {3, SIZE - 1}
	g.head_kind = .King
	g.turn = 0
	g.soup_wait = 0
	g.has_last = false
	g.cursor = g.segs[0]
	place(g, .King, 0, 0)
	minors := [?]Kind{.Knight, .Bishop, .Rook, .Queen, .Knight, .Bishop, .Rook, .Knight, .Bishop}
	for i in 0 ..< min(g.level, len(minors)) {place(g, minors[i], 0, 1)}
	for _ in 0 ..< min(2 + g.level, SIZE) {place(g, .Pawn, 1, 2)}
}

// Soup turns between pea-pawn spills; the soup thickens with each level.
spill_every :: proc(level: int) -> int {
	return max(3, 8 - level)
}

can_move :: proc(g: ^Game) -> bool {
	return g.phase == .Playing && g.soup_wait <= 0
}

@(private)
game_over :: proc(g: ^Game, why: Outcome) {
	g.phase = .Over
	g.outcome = why
	g.soup_wait = 0
	sound(g, .Lose)
	if g.score > g.best {
		g.best = g.score
		g.new_best = true
		g.save_best = true
	}
}

// The player's move. Returns false (and changes nothing) if it is not legal now.
player_move :: proc(g: ^Game, to: Pos) -> bool {
	if !can_move(g) {return false}
	m := player_moves(g)
	if !has(&m, to) {return false}

	eaten := g.soup[to.y][to.x]
	g.soup[to.y][to.x] = .None
	if g.grow > 0 && g.length < MAX_LEN {
		g.length += 1
		g.grow -= 1
	}
	for i := g.length - 1; i > 0; i -= 1 {g.segs[i] = g.segs[i - 1]}
	g.segs[0] = to
	g.cursor = to

	switch eaten {
	case .None:
		sound(g, .Move)
	case .King:
		g.score += KING_BONUS
		g.level += 1
		sound(g, .Level)
		set_note(g, "SOUP KING EATEN!")
		setup_level(g)
		return true
	case .Pawn, .Knight, .Bishop, .Rook, .Queen:
		g.head_kind = eaten
		g.grow += value(eaten)
		g.score += value(eaten)
		sound(g, .Eat)
	}
	if g.head_kind == .Pawn && to.y == 0 {
		g.head_kind = .Queen
		set_note(g, "PROMOTED TO QUEEN!")
	}
	g.soup_wait = SOUP_DELAY
	return true
}

// Simulate one soup move on a copy and score it: taking the head, cutting the stack, staying out
// of the head's reach (the king most of all), closing in, and pawns marching.
@(private)
score_soup_move :: proc(g: ^Game, from, to: Pos) -> int {
	k := soup_at(g, from)
	s := 0
	if idx := pancake_at(g, to); idx == 0 {
		return 100000
	} else if idx > 0 {
		s += 1000 + 50 * (g.length - idx)
	}
	sim := g^
	apply_soup_move(&sim, from, to)
	h := sim.segs[0]
	m := player_moves(&sim)
	worst := 0
	for i in 0 ..< m.n {
		v := sim.soup[m.to[i].y][m.to[i].x]
		w := v == .King ? 1000 : value(v)
		worst = max(worst, w)
	}
	s -= worst * 30
	// Everyone but the king closes in; the king only moves to get out of reach.
	if k != .King {
		h0 := g.segs[0]
		before := max(abs(from.x - h0.x), abs(from.y - h0.y))
		after := max(abs(to.x - h.x), abs(to.y - h.y))
		s += 2 * (before - after)
		if k == .Pawn {s += 1}
	}
	return s
}

// Move a soup piece; a pancake on the destination is cut off, or the game ends if it is the head.
apply_soup_move :: proc(g: ^Game, from, to: Pos) {
	k := g.soup[from.y][from.x]
	g.soup[from.y][from.x] = .None
	if idx := pancake_at(g, to); idx == 0 {
		g.soup[to.y][to.x] = k
		game_over(g, .Eaten)
		return
	} else if idx > 0 {
		g.length = idx
		g.grow = 0
		sound(g, .Cut)
		set_note(g, "THE SOUP CUT YOUR STACK!")
	}
	if k == .Pawn && to.y == SIZE - 1 {k = .Queen}
	g.soup[to.y][to.x] = k
}

// The soup's reply: one piece moves (the best-scoring move, random among ties), then perhaps a
// pea-pawn spills onto the top row. Ends the game if the head is taken or has nowhere to go.
soup_turn :: proc(g: ^Game) {
	if g.phase != .Playing {return}
	g.soup_wait = 0
	best_s := min(int)
	best_from, best_to: Pos
	ties := 0
	for y in 0 ..< SIZE {
		for x in 0 ..< SIZE {
			if g.soup[y][x] == .None {continue}
			from := Pos{x, y}
			m := soup_moves(g, from)
			for i in 0 ..< m.n {
				s := score_soup_move(g, from, m.to[i])
				if s > best_s {
					best_s, best_from, best_to, ties = s, from, m.to[i], 1
				} else if s == best_s {
					ties += 1
					if below(&g.rng, ties) == 0 {best_from, best_to = from, m.to[i]}
				}
			}
		}
	}
	if ties > 0 {
		apply_soup_move(g, best_from, best_to)
		g.last_from, g.last_to, g.has_last = best_from, best_to, true
		if g.phase != .Playing {return}
	}
	g.turn += 1
	if g.turn % spill_every(g.level) == 0 {
		if p, ok := random_empty(g, 0, 0); ok {
			g.soup[p.y][p.x] = .Pawn
			sound(g, .Spill)
		}
	}
	m := player_moves(g)
	if m.n == 0 {game_over(g, .Stuck)}
}

// Player move and, if it was legal, the soup's reply at once (tests and the solver skip the delay).
play_turn :: proc(g: ^Game, to: Pos) -> bool {
	if !player_move(g, to) {return false}
	if g.soup_wait > 0 {soup_turn(g)}
	return true
}

update :: proc(g: ^Game, dt: f32) {
	if g.note_t > 0 {
		g.note_t -= dt
		if g.note_t <= 0 {g.note = ""}
	}
	if g.soup_wait > 0 {
		g.soup_wait -= dt
		if g.soup_wait <= 0 {soup_turn(g)}
	}
}

// A fixed mid-game scene for screenshots and QA: bowl 2, a stack of seven, the head moving as a rook.
demo :: proc(g: ^Game) {
	new_game(g)
	g.level = 2
	g.score = 14
	g.soup = {}
	trail := [?]Pos{{2, 4}, {2, 5}, {3, 6}, {4, 6}, {5, 5}, {5, 4}, {4, 3}}
	g.length = len(trail)
	for p, i in trail {g.segs[i] = p}
	g.grow = 2
	g.head_kind = .Rook
	g.cursor = trail[0]
	g.soup[0][5] = .King
	g.soup[1][1] = .Knight
	g.soup[1][6] = .Bishop
	g.soup[2][2] = .Pawn
	g.soup[2][4] = .Pawn
	g.soup[1][7] = .Pawn
	g.soup[3][0] = .Pawn
}

// --- Input ------------------------------------------------------------------------------------

input :: proc(g: ^Game, a: Action) {
	switch g.phase {
	case .Title, .Over:
		if a == .Confirm {new_game(g)}
	case .Playing:
		if !g.cursor_on {
			g.cursor_on = true
			if a != .Confirm {return}
		}
		switch a {
		case .Up: g.cursor.y = max(0, g.cursor.y - 1)
		case .Down: g.cursor.y = min(SIZE - 1, g.cursor.y + 1)
		case .Left: g.cursor.x = max(0, g.cursor.x - 1)
		case .Right: g.cursor.x = min(SIZE - 1, g.cursor.x + 1)
		case .Confirm: player_move(g, g.cursor)
		}
	}
}

// A tap or click in logical pixels.
click :: proc(g: ^Game, x, y: int) {
	switch g.phase {
	case .Title, .Over:
		new_game(g)
	case .Playing:
		g.cursor_on = false
		if x < BOARD_X || y < BOARD_Y {return}
		p := Pos{(x - BOARD_X) / TILE, (y - BOARD_Y) / TILE}
		if in_board(p) {player_move(g, p)}
	}
}
