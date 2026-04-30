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

## Post-commit links

After each commit, always show these links to the user:

- Play the games: https://rubentipparach.github.io/tic-labs/
- Track CI builds: https://github.com/RubenTipparach/tic-labs/actions
