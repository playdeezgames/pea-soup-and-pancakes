# Pea Soup and Pancakes: design

Chess crossed with Snake, set at the Swedish Thursday lunch of pea soup followed by pancakes (*ärtsoppa och pannkakor*). The concept and the user's decisions are also recorded in the vault: `splorr/Concepts/Pea Soup and Pancakes.md` and `splorr/Games/Pea Soup and Pancakes.md`.

## The user's rules (November 19, 2026)

- Single player, turn-based, 8×8 board ("You Are What You Eat").
- You are a growing **stack of pancakes**. **The head moves like the chess piece it ate last.** Before its first meal it moves like a **king**.
- **Trail: landing squares only.** The body fills the squares the head has landed on, in order. A knight's trail has gaps, and a slide leaves nothing on the squares it crossed.
- **Growth by chess value:** pawn +1, knight or bishop +3, rook +5, queen +9, added one pancake per move.
- Your own body blocks your slides and can't be landed on.
- The **soup side's** pieces move by chess rules, **one piece per turn**. A soup piece that captures a body segment cuts the stack there (that segment and everything behind it is lost). One that captures the head ends the game.
- Pea-pawns spill from the pot onto the top row now and then and march down.
- **Eat the soup king to clear the level** (a "bowl"). The next bowl's soup is thicker.

## Choices made while building (provisional: the user has not confirmed them)

- **The soup king cannot eat pancakes**, so you can trap it by wrapping your stack round it. Without this, a lone pancake piece could never corner a fleeing king (it's chess's "no mate with one piece" problem). A one-turn-lookahead bot cleared no bowls in 400 games with the king able to eat pancakes, and reached bowl 4 with this rule.
- Each bowl starts afresh: a stack of one, moving as a king, at the bottom centre. The score carries over.
- Score: each meal's chess value, plus 10 for a soup king.
- A pancake pawn moves up the board (towards the soup), eats diagonally forward and becomes a queen on the top row. Pea-pawns move down and become queens on the bottom row.
- The head is stuck when it has no legal move (a pawn with nothing in front of it, say), and that ends the game ("your stack went cold").
- **Soup AI:** it takes the head if it can, then prefers the longest cut. Otherwise every piece but the king closes in on the head, and nothing steps into the head's reach. The soup king moves only to get out of reach. Ties are broken at random.
- **Thickening:** bowl n starts with the king, the first n of knight, bishop, rook, queen, knight, bishop, rook, knight, bishop, and 2 + n pawns (at most 8). Pea-pawns spill every max(3, 8 − n) soup turns.
- Red squares show where the soup could bite next turn. Dots and gold boxes show your legal moves.
- Best score is kept in `localStorage` under `pea-soup-and-pancakes:best`.
