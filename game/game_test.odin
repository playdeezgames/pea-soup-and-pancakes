#+build !js
package game

import "core:testing"

// An empty board with the head at p (king-moving, length 1) and nothing else.
@(private = "file")
bare :: proc(p: Pos) -> Game {
	g := title(1)
	g.phase = .Playing
	g.level = 1
	g.length = 1
	g.segs[0] = p
	g.head_kind = .King
	return g
}

@(test)
king_start_has_five_moves_from_the_bottom_edge :: proc(t: ^testing.T) {
	g := bare({3, 7})
	m := player_moves(&g)
	testing.expect_value(t, m.n, 5)
}

@(test)
new_level_has_one_king_and_a_king_moving_head :: proc(t: ^testing.T) {
	g := title(42)
	for level in 1 ..= 12 {
		g.level = level
		setup_level(&g)
		kings := 0
		for y in 0 ..< SIZE {
			for x in 0 ..< SIZE {
				if g.soup[y][x] == .King {kings += 1}
			}
		}
		testing.expect_value(t, kings, 1)
		testing.expect_value(t, g.head_kind, Kind.King)
		testing.expect_value(t, g.length, 1)
		testing.expect_value(t, g.soup[7][3], Kind.None)
	}
}

@(test)
eating_a_piece_makes_the_head_move_like_it_and_grows_by_its_value :: proc(t: ^testing.T) {
	g := bare({3, 7})
	g.soup[6][3] = .Knight
	testing.expect(t, play_turn(&g, {3, 6}))
	testing.expect_value(t, g.head_kind, Kind.Knight)
	testing.expect_value(t, g.grow, 3)
	testing.expect_value(t, g.score, 3)
	// Knight jump: the trail holds landing squares only, with a gap between them.
	testing.expect(t, play_turn(&g, {4, 4}))
	testing.expect_value(t, g.length, 2)
	testing.expect_value(t, g.segs[0], Pos{4, 4})
	testing.expect_value(t, g.segs[1], Pos{3, 6})
}

@(test)
growth_adds_one_pancake_per_move :: proc(t: ^testing.T) {
	g := bare({0, 7})
	g.soup[7][1] = .Rook
	testing.expect(t, play_turn(&g, {1, 7}))
	testing.expect_value(t, g.grow, 5)
	path := [?]Pos{{1, 6}, {2, 6}, {2, 5}, {3, 5}, {3, 4}, {4, 4}}
	for p in path {
		g.head_kind = .King // walk one square at a time
		testing.expect(t, play_turn(&g, p))
	}
	testing.expect_value(t, g.length, 6)
	testing.expect_value(t, g.grow, 0)
}

@(test)
own_body_blocks_a_slide_and_cannot_be_landed_on :: proc(t: ^testing.T) {
	g := bare({0, 7})
	g.head_kind = .Rook
	g.length = 2
	g.segs[1] = {0, 4}
	m := player_moves(&g)
	testing.expect(t, has(&m, {0, 5}))
	testing.expect(t, !has(&m, {0, 4}))
	testing.expect(t, !has(&m, {0, 3}))
	testing.expect(t, has(&m, {7, 7}))
}

@(test)
a_slide_stops_on_the_soup_piece_it_eats :: proc(t: ^testing.T) {
	g := bare({0, 7})
	g.head_kind = .Bishop
	g.soup[5][2] = .Pawn
	m := player_moves(&g)
	testing.expect(t, has(&m, {2, 5}))
	testing.expect(t, !has(&m, {3, 4}))
}

@(test)
pancake_pawn_walks_up_eats_diagonally_and_promotes :: proc(t: ^testing.T) {
	g := bare({3, 1})
	g.head_kind = .Pawn
	g.soup[0][3] = .Rook // blocks the step forward
	m := player_moves(&g)
	testing.expect_value(t, m.n, 0)
	g.soup[0][3] = .None
	g.soup[0][4] = .Pawn
	m = player_moves(&g)
	testing.expect_value(t, m.n, 2)
	testing.expect(t, player_move(&g, {4, 0}))
	testing.expect_value(t, g.head_kind, Kind.Queen)
}

@(test)
soup_cuts_the_stack_where_it_captures :: proc(t: ^testing.T) {
	g := bare({3, 3})
	g.length = 4
	g.segs[1] = {3, 4}
	g.segs[2] = {3, 5}
	g.segs[3] = {3, 6}
	g.soup[5][0] = .Rook
	apply_soup_move(&g, {0, 5}, {3, 5})
	testing.expect_value(t, g.length, 2)
	testing.expect_value(t, g.phase, Phase.Playing)
	testing.expect_value(t, g.soup[5][3], Kind.Rook)
}

@(test)
soup_takes_the_head_when_it_can :: proc(t: ^testing.T) {
	g := bare({3, 3})
	g.soup[0][3] = .Rook
	g.soup[0][7] = .King
	soup_turn(&g)
	testing.expect_value(t, g.phase, Phase.Over)
	testing.expect_value(t, g.outcome, Outcome.Eaten)
}

@(test)
soup_king_flees_the_head :: proc(t: ^testing.T) {
	g := bare({3, 2})
	g.soup[0][3] = .King // a king-moving head two squares away could reach it next turn if it steps down
	soup_turn(&g)
	testing.expect_value(t, g.soup[0][3], Kind.None)
	kpos := Pos{-1, -1}
	for y in 0 ..< SIZE {
		for x in 0 ..< SIZE {
			if g.soup[y][x] == .King {kpos = {x, y}}
		}
	}
	m := player_moves(&g)
	testing.expect(t, !has(&m, kpos))
}

@(test)
soup_closes_in_instead_of_the_king_wandering :: proc(t: ^testing.T) {
	g := bare({3, 7})
	g.soup[0][7] = .King
	g.soup[0][0] = .Rook
	soup_turn(&g)
	testing.expect_value(t, g.soup[0][7], Kind.King) // safe, so it stays put
	testing.expect_value(t, g.soup[0][0], Kind.None) // the rook moved towards the head
}

@(test)
pea_pawn_marches_down_and_promotes :: proc(t: ^testing.T) {
	g := bare({0, 0})
	g.soup[6][5] = .Pawn
	m := soup_moves(&g, {5, 6})
	testing.expect_value(t, m.n, 1)
	apply_soup_move(&g, {5, 6}, {5, 7})
	testing.expect_value(t, g.soup[7][5], Kind.Queen)
}

@(test)
eating_the_soup_king_clears_the_level :: proc(t: ^testing.T) {
	g := bare({3, 1})
	g.length = 3
	g.segs[1] = {3, 2}
	g.segs[2] = {3, 3}
	g.soup[0][3] = .King
	testing.expect(t, player_move(&g, {3, 0}))
	testing.expect_value(t, g.level, 2)
	testing.expect_value(t, g.score, KING_BONUS)
	testing.expect_value(t, g.length, 1)
	testing.expect_value(t, g.head_kind, Kind.King)
	testing.expect_value(t, g.soup_wait, f32(0)) // the new level starts on the player's move
}

@(test)
no_legal_move_ends_the_game :: proc(t: ^testing.T) {
	g := bare({0, 0})
	g.head_kind = .Pawn // a pawn on the top row with nothing to eat cannot move
	g.soup[7][7] = .King
	soup_turn(&g)
	testing.expect_value(t, g.phase, Phase.Over)
	testing.expect_value(t, g.outcome, Outcome.Stuck)
}

@(test)
illegal_moves_change_nothing :: proc(t: ^testing.T) {
	g := bare({3, 7})
	before := g
	testing.expect(t, !player_move(&g, {3, 5}))
	testing.expect(t, !player_move(&g, {9, 9}))
	testing.expect_value(t, g.segs[0], before.segs[0])
	testing.expect_value(t, g.length, before.length)
}

// Random legal play for many games: the board stays consistent and every game ends.
@(test)
soak_random_games_keep_the_board_consistent :: proc(t: ^testing.T) {
	g := title(7)
	pick := Rng{99}
	finished := 0
	for _ in 0 ..< 300 {
		new_game(&g)
		turns := 0
		for g.phase == .Playing && turns < 2000 {
			m := player_moves(&g)
			if !testing.expect(t, m.n > 0) {return}
			// Prefer eating sometimes so levels get cleared.
			to := m.to[below(&pick, m.n)]
			for i in 0 ..< m.n {
				if g.soup[m.to[i].y][m.to[i].x] != .None && below(&pick, 2) == 0 {to = m.to[i]}
			}
			testing.expect(t, play_turn(&g, to))
			turns += 1
			if g.phase != .Playing {break}
			testing.expect(t, g.length >= 1 && g.length <= MAX_LEN)
			for i in 0 ..< g.length {
				p := g.segs[i]
				testing.expect(t, in_board(p))
				testing.expect_value(t, g.soup[p.y][p.x], Kind.None)
				for j in i + 1 ..< g.length {testing.expect(t, g.segs[j] != p)}
			}
		}
		if g.phase == .Over {finished += 1}
	}
	testing.expect(t, finished > 0)
}

@(test)
soup_king_cannot_eat_pancakes_so_a_stack_can_trap_it :: proc(t: ^testing.T) {
	// King in the corner, wrapped by the stack on all three neighbours.
	g := bare({1, 1})
	g.length = 3
	g.segs[1] = {1, 0}
	g.segs[2] = {0, 1}
	g.soup[0][0] = .King
	m := soup_moves(&g, {0, 0})
	testing.expect_value(t, m.n, 0)
	testing.expect(t, play_turn(&g, {0, 0}))
	testing.expect_value(t, g.level, 2)
}
