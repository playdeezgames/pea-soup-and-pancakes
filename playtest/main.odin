// Strategy play-tester: scripted players over many games on the real rules (package game), native only.
//
//   odin run playtest -collection:psp=. -o:speed -- [games]
//
// Each strategy scores every legal move by simulating it plus the soup's reply. The simulated reply
// uses a different random seed from the real one, so the bot cannot see the soup's actual tie-breaks.
#+build !js
package main

import "core:fmt"
import "core:os"
import "core:strconv"
import "psp:game"

Kind :: game.Kind
Pos :: game.Pos

Weights :: struct {
	name:         string,
	lookahead:    bool, // simulate the soup's reply
	safety:       int, // penalty if the head is threatened after the reply
	score:        int, // per point gained
	length:       int, // per pancake of stack (after cuts)
	cut:          int, // penalty per pancake lost to a cut
	king_dist:    int, // penalty per square of distance to the soup king
	king_moves:   int, // penalty per legal soup-king move
	head_moves:   int, // bonus per legal move the head will have
	pawn_head:    int, // penalty for moving as a pawn
	slider_head:  int, // bonus for moving as a rook, bishop or queen
	knight_head:  int, // bonus for moving as a knight
	queen_head:   int, // extra bonus for a queen
	greedy_eat:   bool, // no lookahead: eat the most valuable thing in reach
}

Stats :: struct {
	games, bowls_cleared, score, turns, best_score, max_bowl: int,
	eaten, stuck, timeout: int,
	clears_by_head:  [Kind]int, // the head's piece when it ate the soup king
	king_moves_at_clear: [9]int, // soup-king legal moves on the turn before it was eaten
	len_at_clear:    int,
	cuts, cut_lost:  int,
	deaths_by_head:  [Kind]int,
	turns_as:        [Kind]int, // player turns spent moving as each piece
	bowl_reached:    [16]int, // games that reached bowl n
	turns_in_bowl1:  int,
	bowl1_clears:    int,
	meals:           [Kind]int, // meals of each kind (not the king)
	died_after:      [Kind]int, // ...followed by the game ending within 3 turns
	pawn_top, pawn_top_fatal: int, // pawn meals on the top row (instant queen) and how many ended the game within 3 turns
	forced_meals: int, // meals where every other move lost the head
	king_free_at_clear: [9]int, // soup-king moves that would NOT be in the head's reach, turn before it was eaten
}

bot_rng := game.Rng{12345}
dump_stall := false

dump :: proc(g: ^game.Game) {
	CH := [Kind]u8{.None = '.', .Pawn = 'p', .Knight = 'n', .Bishop = 'b', .Rook = 'r', .Queen = 'q', .King = 'k'}
	fmt.printfln("  stalled game: bowl %d, head moves as %v, stack %d", g.level, g.head_kind, g.length)
	for y in 0 ..< game.SIZE {
		fmt.print("   ")
		for x in 0 ..< game.SIZE {
			c := CH[g.soup[y][x]]
			if i := game.pancake_at(g, {x, y}); i == 0 {c = 'H'} else if i > 0 {c = 'o'}
			fmt.printf("%c ", c)
		}
		fmt.println()
	}
}

king_pos :: proc(g: ^game.Game) -> (Pos, bool) {
	for y in 0 ..< game.SIZE {
		for x in 0 ..< game.SIZE {
			if g.soup[y][x] == .King {return {x, y}, true}
		}
	}
	return {}, false
}

king_mobility :: proc(g: ^game.Game) -> int {
	if k, ok := king_pos(g); ok {
		m := game.soup_moves(g, k)
		return m.n
	}
	return 0
}

// Soup-king moves to squares the head could not reach next turn (its real escape squares).
king_free :: proc(g: ^game.Game) -> int {
	kp, ok := king_pos(g)
	if !ok {return 0}
	km := game.soup_moves(g, kp)
	free := 0
	for i in 0 ..< km.n {
		sim := g^
		sim.soup[kp.y][kp.x] = .None
		sim.soup[km.to[i].y][km.to[i].x] = .King
		pm := game.player_moves(&sim)
		if !game.has(&pm, km.to[i]) {free += 1}
	}
	return free
}

evaluate :: proc(g: ^game.Game, to: Pos, w: ^Weights) -> int {
	if w.greedy_eat {
		k := g.soup[to.y][to.x]
		s := int(game.below(&bot_rng, 3))
		if k == .King {s += 1000} else {s += 10 * game.value(k)}
		return s
	}
	sim := g^
	sim.rng = {game.next(&bot_rng)}
	level := sim.level
	len0 := g.length + g.grow
	game.player_move(&sim, to)
	if sim.level > level {return 1_000_000} // ate the soup king
	if w.lookahead && sim.soup_wait > 0 {game.soup_turn(&sim)}
	if sim.phase != .Playing {return -1_000_000}
	s := int(game.below(&bot_rng, 3))
	h := sim.segs[0]
	if w.safety != 0 {
		t := game.threats(&sim)
		if t[h.y][h.x] {s -= w.safety}
	}
	s += w.score * (sim.score - g.score)
	s += w.length * (sim.length + sim.grow)
	lost := max(0, len0 + (sim.score - g.score) - (sim.length + sim.grow))
	s -= w.cut * lost
	if kp, ok := king_pos(&sim); ok {
		s -= w.king_dist * max(abs(kp.x - h.x), abs(kp.y - h.y))
		s -= w.king_moves * king_mobility(&sim)
	}
	if w.head_moves != 0 {
		m := game.player_moves(&sim)
		s += w.head_moves * min(m.n, 8)
	}
	switch sim.head_kind {
	case .Pawn: s -= w.pawn_head
	case .Rook, .Bishop: s += w.slider_head
	case .Queen: s += w.slider_head + w.queen_head
	case .Knight: s += w.knight_head
	case .King, .None:
	}
	return s
}

play :: proc(w: ^Weights, games: int, seed: u64) -> (st: Stats) {
	g := game.title(seed)
	for _ in 0 ..< games {
		game.new_game(&g)
		st.games += 1
		turns := 0
		bowl1_turns := 0
		last_meal := Kind.None
		meal_turn := -100
		top_meal_turn := -100
		for g.phase == .Playing && turns < 3000 {
			m := game.player_moves(&g)
			best, bs := 0, min(int)
			for i in 0 ..< m.n {
				s := evaluate(&g, m.to[i], w)
				if s > bs {best, bs = i, s}
			}
			to := m.to[best]
			kmob := king_mobility(&g)
			head := g.head_kind
			length := g.length
			level := g.level
			len_before := g.length + g.grow
			st.turns_as[head] += 1
			meal := g.soup[to.y][to.x]
			kfree := king_free(&g)
			game.play_turn(&g, to)
			if meal == .Pawn && to.y == 0 {st.pawn_top += 1; top_meal_turn = turns + 1}
			if meal != .None && meal != .King {
				st.meals[meal] += 1
				last_meal, meal_turn = meal, turns
			}
			turns += 1
			if level == 1 {bowl1_turns += 1}
			if g.level > level {
				st.bowls_cleared += 1
				st.clears_by_head[head] += 1
				st.king_moves_at_clear[min(kmob, 8)] += 1
				st.king_free_at_clear[min(kfree, 8)] += 1
				st.len_at_clear += length
				if level == 1 {st.bowl1_clears += 1}
			} else if g.phase == .Playing && g.length + g.grow < len_before {
				st.cuts += 1
				st.cut_lost += len_before - (g.length + g.grow)
			}
			if g.phase == .Over {
				st.deaths_by_head[g.head_kind] += 1
				if turns - meal_turn <= 3 {st.died_after[last_meal] += 1}
				if turns - top_meal_turn <= 2 {st.pawn_top_fatal += 1}
			}
		}
		if g.phase == .Playing {
			st.timeout += 1
			if dump_stall {dump(&g); dump_stall = false}
		}
		if g.outcome == .Eaten {st.eaten += 1}
		if g.outcome == .Stuck {st.stuck += 1}
		st.score += g.score
		st.turns += turns
		st.turns_in_bowl1 += bowl1_turns
		st.best_score = max(st.best_score, g.score)
		st.max_bowl = max(st.max_bowl, g.level)
		for b in 1 ..= min(g.level, len(st.bowl_reached) - 1) {st.bowl_reached[b] += 1}
	}
	return
}

pct :: proc(a, b: int) -> f64 {return b == 0 ? 0 : 100 * f64(a) / f64(b)}

report :: proc(w: ^Weights, st: ^Stats) {
	n := f64(st.games)
	fmt.printf("%-14s bowls/game %5.2f  clear bowl1 %5.1f%%  bowl3+ %5.1f%%  max %2d  score %6.1f (best %3d)  turns %6.1f  eaten %5.1f%% stuck %5.1f%% cuts/game %4.2f",
		w.name, f64(st.bowls_cleared) / n, pct(st.bowl1_clears, st.games), pct(st.bowl_reached[3], st.games), st.max_bowl,
		f64(st.score) / n, st.best_score, f64(st.turns) / n, pct(st.eaten, st.games), pct(st.stuck, st.games), f64(st.cuts) / n)
	if st.timeout > 0 {fmt.printf("  timeout %d", st.timeout)}
	fmt.println()
}

detail :: proc(w: ^Weights, st: ^Stats) {
	fmt.printfln("  [%s] king eaten while moving as:", w.name)
	for k in Kind {
		if st.clears_by_head[k] > 0 {fmt.printf("    %v %d (%.0f%%)", k, st.clears_by_head[k], pct(st.clears_by_head[k], st.bowls_cleared))}
	}
	fmt.println()
	fmt.printf("  soup-king legal moves just before it was eaten:")
	for c, i in st.king_moves_at_clear {if c > 0 {fmt.printf(" %d:%d", i, c)}}
	fmt.println()
	if st.bowls_cleared > 0 {fmt.printfln("  average stack when the king was eaten: %.1f", f64(st.len_at_clear) / f64(st.bowls_cleared))}
	total := 0
	for k in Kind {total += st.turns_as[k]}
	fmt.printf("  share of turns / deaths per head piece:")
	for k in Kind {
		if st.turns_as[k] > 0 {fmt.printf("  %v %.0f%%/%d", k, pct(st.turns_as[k], total), st.deaths_by_head[k])}
	}
	fmt.println()
	fmt.printf("  meals (and game over within 3 turns):")
	for k in Kind {
		if st.meals[k] > 0 {fmt.printf("  %v %d (%.0f%% fatal)", k, st.meals[k], pct(st.died_after[k], st.meals[k]))}
	}
	fmt.println()
	fmt.printfln("  of the pawn meals, %d were on the top row (instant queen), %.0f%% of those fatal", st.pawn_top, pct(st.pawn_top_fatal, st.pawn_top))
	fmt.printf("  soup-king escape squares (out of the head's reach) the turn before it was eaten:")
	for c, i in st.king_free_at_clear {if c > 0 {fmt.printf(" %d:%d", i, c)}}
	fmt.println()
	if st.bowl1_clears > 0 {fmt.printfln("  average turns spent in bowl 1: %.1f", f64(st.turns_in_bowl1) / f64(st.games))}
	fmt.printf("  games reaching bowl:")
	for c, b in st.bowl_reached {if b >= 2 && c > 0 {fmt.printf(" %d:%d", b, c)}}
	fmt.println()
}

main :: proc() {
	games := 500
	if len(os.args) > 1 {
		if v, ok := strconv.parse_int(os.args[1]); ok {games = v}
	}
	strategies := [?]Weights {
		{name = "random"},
		{name = "greedy-eat", greedy_eat = true},
		{name = "survivor", lookahead = true, safety = 500},
		{name = "glutton", lookahead = true, safety = 500, score = 20, cut = 10},
		{name = "hunter", lookahead = true, safety = 500, score = 20, cut = 10, king_dist = 6},
		{name = "trapper", lookahead = true, safety = 500, score = 20, cut = 10, king_dist = 6, king_moves = 15, head_moves = 3},
		{name = "trap-nopawn", lookahead = true, safety = 500, score = 20, cut = 10, king_dist = 6, king_moves = 15, head_moves = 3, pawn_head = 60},
		{name = "trap-slider", lookahead = true, safety = 500, score = 20, cut = 10, king_dist = 6, king_moves = 15, head_moves = 3, pawn_head = 60, slider_head = 40, queen_head = 30},
		{name = "trap-knight", lookahead = true, safety = 500, score = 20, cut = 10, king_dist = 6, king_moves = 15, head_moves = 3, pawn_head = 60, knight_head = 40},
		{name = "snake-long", lookahead = true, safety = 500, score = 20, cut = 10, length = 15, king_dist = 6, king_moves = 15, head_moves = 3, pawn_head = 60},
		{name = "reckless", lookahead = true, safety = 0, score = 20, cut = 10, king_dist = 6, king_moves = 15, head_moves = 3},
		{name = "wary", lookahead = true, safety = 60, score = 20, cut = 10, king_dist = 6, king_moves = 15, head_moves = 3},
		{name = "reck-nopawn", lookahead = true, score = 20, cut = 10, king_dist = 6, king_moves = 15, head_moves = 3, pawn_head = 60},
		{name = "reck-slider", lookahead = true, score = 20, cut = 10, king_dist = 6, king_moves = 15, head_moves = 3, pawn_head = 60, slider_head = 40, queen_head = 30},
		{name = "reck-knight", lookahead = true, score = 20, cut = 10, king_dist = 6, king_moves = 15, head_moves = 3, pawn_head = 60, knight_head = 40},
		{name = "reck-long", lookahead = true, score = 20, cut = 10, length = 15, king_dist = 6, king_moves = 15, head_moves = 3, pawn_head = 60},
		{name = "reck-chase", lookahead = true, score = 20, cut = 10, king_dist = 12, head_moves = 3},
		{name = "reck-squeeze", lookahead = true, score = 20, cut = 10, king_dist = 3, king_moves = 40, head_moves = 3},
		{name = "reck-noscore", lookahead = true, cut = 10, king_dist = 6, king_moves = 15, head_moves = 3},
		{name = "king-only", lookahead = true, score = -40, cut = 10, king_dist = 6, king_moves = 15, head_moves = 3},
		{name = "never-pawn", lookahead = true, score = 20, cut = 10, king_dist = 6, king_moves = 15, head_moves = 3, pawn_head = 100000, slider_head = 40, queen_head = 30},
		{name = "big-meals", lookahead = true, score = 20, cut = 10, king_dist = 6, king_moves = 15, head_moves = 3, pawn_head = 100000, knight_head = -30, slider_head = 60, queen_head = 60},
		{name = "reck-nomob", lookahead = true, score = 20, cut = 10, king_dist = 6, king_moves = 15},
	}
	only := ""
	dump_stall = len(os.args) > 3
	if len(os.args) > 2 {only = os.args[2]}
	for &w in strategies {
		if only != "" && only != "all" && w.name != only {continue}
		st := play(&w, games, 2026_11_19)
		report(&w, &st)
		if only != "" {detail(&w, &st)}
	}
}
