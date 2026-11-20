# Pea Soup and Pancakes: strategy

From play-testing on November 20, 2026: scripted players over 600 games each on the real rules (`playtest/`), plus hand play in the browser. Rerun with:

```bash
odin build playtest -collection:psp=. -o:speed -out:build/playtest
build/playtest 600              # every strategy, one line each
build/playtest 600 big-meals    # one strategy with detail
build/playtest 120 big-meals x  # ...and print the board of the first stalled game
```

## The strategies that work

1. **Never land on a red square.** Every scripted player that looked one turn ahead survived for hundreds of turns. The ones that didn't (random, and greedy "eat what's in reach") died in about 6 turns, almost always by walking into a capture.
2. **Ignore red squares that aren't where you're landing.** Players that also avoided ending near danger turtled and cleared almost nothing (0 to 1% of bowl 1s). You always move before the soup does, so being next to danger is fine as long as you don't land in it.
3. **Go straight for the soup king. It can't hurt you.** It can't eat pancakes, and that includes the head, so walking right up to it is safe from the king itself. The best players caught it with a stack of only 1 to 1.5 pancakes. In hand play, three bowls in a row fell in about 6 moves each without eating a single pea.
4. **Trap it against the edge.** In 1,048 of 1,059 captures the king had no escape square the turn before it was eaten. Its own peas and the board edge do most of the boxing in. The key position is **directly in front of a king on the back row** (or diagonally in front of a cornered king). From there a king-moving head reaches every square the king could flee to. The soup's guards usually arrive a move too late.
5. **Stay a king unless a meal is clearly good.** The best players spent 87 to 97% of their turns moving as a king. Mobility matters: dropping the "keep moves open" weight cut bowls per game from 1.17 to 0.69.
6. **Eat pawns only on the top row.** A pawn meal anywhere else was fatal within three turns about 76% of the time: the head can only go up and gets stuck or caught. A pawn eaten on the top row turns the head straight into a **queen**: 610 such meals, 1% fatal. The pot's new spills on the top row are free queens.
7. **Bigger meals are safer meals.** Within three turns, knight meals were fatal 8% of the time, bishops 3%, rooks 3% and queens 0%. Preferring sliders and queens edged out the other strategies (1.92 bowls per game, against 1.84 for "stay a king and avoid pawns"). It's a small gain; the real gains come from rules 1 to 4.
8. **Look at the board after every soup move.** Sliders cross the board in one turn. The one hand-played death came from queueing two moves without looking.

## Results (600 games each, bowls cleared per game)

| Strategy | Bowls/game | Clears bowl 1 | Reaches bowl 3 | Notes |
|---|---|---|---|---|
| random | 0.00 | 0% | 0% | dies in about 6 turns |
| greedy eat | 0.00 | 0% | 0% | dies in about 6 turns |
| survivor (avoid ending near danger) | 0.01 | 1% | 0% | turtles |
| wary (mild version of that) | 0.58 | 42% | 14% | |
| hunter (approach the king) | 0.33 | 27% | 6% | still turtles a bit |
| reckless (lookahead only, approach and squeeze the king, keep moves open) | 1.17 | 74% | 34% | |
| ...without the moves-open weight | 0.69 | 49% | 16% | |
| ...never eating anything but the king | 1.76 | 94% | 63% | |
| ...avoiding pawn heads | 1.84 | 94% | 65% | |
| ...also preferring sliders and queens ("big-meals") | 1.92 | 95% | 68% | best |

The furthest any player got was bowl 7. The best score was 100.

## Observations for the designer (not changes)

- **Optimal play mostly ignores the Snake half.** The strongest play moves as a king and catches the soup king with a one-pancake stack. Growing, the trail and cuts barely figure. That may be fine, or the user may want to give the stack a job.
- **Once you know the back-row trap, bowls are short.** By hand it took about 6 moves per bowl, and the soup's guards arrived a move late each time.
- **Pawn gridlock.** In roughly 1 game in 10 the scripted players hit the 3,000-turn cap. Pea-pawns spill faster than they can march, jam into a wall that guards itself diagonally, and the king hides behind it. Neither side can make progress.
- **Fixed on November 20, 2026:** the red tint used to mark the squares around the soup king, which can't eat pancakes. Those warnings were false and steered human players away from the right approach. Bots weren't affected (they checked only the head's landing square).
