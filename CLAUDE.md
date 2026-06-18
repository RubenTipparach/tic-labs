# CLAUDE.md

## No em dashes

Never use em dashes (—) anywhere: not in chat replies, not in commit
messages, not in code comments, not in PR descriptions, not in in-game
text or UI strings, not in documentation. Use a comma, a colon, a period,
parentheses, or a regular hyphen-minus (-) instead. This applies to all
text generated for this repo or this user.

## PICO-8 carts must include a __label__

Every `cart.p8` under `games/` must contain a `__label__` section
(128 lines of 128 hex chars) between `__gfx__` and `__sfx__`. PICO-8's
HTML export refuses to run without one and prints "please capture a
label first", which fails the deploy build. See `games/pico8-snake/cart.p8`
for the expected format. When authoring a new cart from scratch, add a
placeholder label (a 128x128 black field is fine) so the build passes,
then capture a real label later in PICO-8.

## TIC-80 SWEETIE-16 palette

TIC-80 carts are locked to a 16-color indexed palette. Picking colors
outside this set looks washed out or off-key, so prefer indices 0..15
when authoring sprites, UI, or particle effects. Index, hex, and the
short name to use in comments:

| # | hex      | name        |
|---|----------|-------------|
| 0 | #1a1c2c  | black       |
| 1 | #5d275d  | purple      |
| 2 | #b13e53  | red         |
| 3 | #ef7d57  | orange      |
| 4 | #ffcd75  | yellow      |
| 5 | #a7f070  | light green |
| 6 | #38b764  | green       |
| 7 | #257179  | dark teal   |
| 8 | #29366f  | dark blue   |
| 9 | #3b5dc9  | blue        |
| 10| #41a6f6  | light blue  |
| 11| #73eff7  | cyan        |
| 12| #f4f4f4  | white       |
| 13| #94b0c2  | light gray  |
| 14| #566c86  | gray        |
| 15| #333c57  | dark gray   |

Common pairings: 0/15 for backgrounds and shadows, 12/13 for foreground
text, 11/10/9/8 for friendly ships and water, 2/3/4 for hostile ships
and explosions, 5/6/7 for organics and salvage. Avoid using index 14
for player UI text, it disappears against dark backgrounds.

## Game thumbnails

Take a screenshot of each game and use it as the gallery thumbnail. Save
it as `thumbnail.png` (or `screenshot.png`) in the game's folder under
`games/`. The build copies it to `docs/<slug>/thumb.png` and renders it as
the card image; when no image is present the card falls back to the
`thumbnail_color` from `meta.json`. Prefer a real screenshot at the game's
native resolution (128x128 for PICO-8 and TIC-80) so it scales crisply
with pixel-art rendering. For PICO-8, the cart `__label__` is itself a
captured screenshot, so capturing a good label in PICO-8 doubles as the
thumbnail source. When you cannot run the engine to capture a live frame,
render a faithful frame from the game's own draw code (same layout, sprites,
and palette) as a stand-in, and replace it with a real capture later.

## Post-commit links

After each commit, always show these links to the user:

- Play the games: https://rubentipparach.github.io/tic-labs/
- Track CI builds: https://github.com/RubenTipparach/tic-labs/actions
