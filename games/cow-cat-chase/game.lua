-- title:  Cow Cat Chase
-- author: tic-labs
-- desc:   A cow-print cat chases a baby cat
-- script: lua

-- screen: 240x136, top 8px reserved for HUD
local SW, SH = 240, 136
local PLAY_TOP = 10
local PLAY_BOTTOM = SH - 2

-- entities
local cow = {x = 40, y = 70, vx = 0, vy = 0, facing = 1}
local baby = {x = 180, y = 70, vx = 0, vy = 0, facing = -1, wiggle = 0}

-- gameplay
local score = 0
local high_score = 0
local time_left = 0
local GAME_TIME = 60 * 60  -- 60 seconds at 60fps
local state = "title"
local catch_flash = 0
local hearts = {}
local meows = {}

local COW_SPEED = 1.4
local BABY_BASE_SPEED = 1.1
local CATCH_DIST = 7

function init_game()
  cow.x = 40
  cow.y = 70
  cow.vx = 0
  cow.vy = 0
  cow.facing = 1
  baby.x = 180
  baby.y = 70
  baby.vx = 0
  baby.vy = 0
  baby.facing = -1
  baby.wiggle = 0
  score = 0
  time_left = GAME_TIME
  catch_flash = 0
  hearts = {}
  meows = {}
  state = "playing"
end

function TIC()
  if state == "title" then
    update_title()
    draw_title()
  elseif state == "playing" then
    update_game()
    draw_game()
  elseif state == "over" then
    update_over()
    draw_game()
    draw_over_overlay()
  end
end

function update_title()
  if btnp(4) then init_game() end
end

function update_game()
  -- player input (cow cat)
  local ax, ay = 0, 0
  if btn(0) then ay = ay - 1 end
  if btn(1) then ay = ay + 1 end
  if btn(2) then ax = ax - 1; cow.facing = -1 end
  if btn(3) then ax = ax + 1; cow.facing = 1 end
  if ax ~= 0 and ay ~= 0 then
    -- normalize diagonal
    ax = ax * 0.7071
    ay = ay * 0.7071
  end
  cow.vx = ax * COW_SPEED
  cow.vy = ay * COW_SPEED
  cow.x = cow.x + cow.vx
  cow.y = cow.y + cow.vy
  cow.x = clamp(cow.x, 4, SW - 5)
  cow.y = clamp(cow.y, PLAY_TOP + 4, PLAY_BOTTOM - 4)

  -- baby cat AI: flee from cow with some panic
  local dx = baby.x - cow.x
  local dy = baby.y - cow.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local speed = BABY_BASE_SPEED + math.min(score * 0.04, 1.2)
  -- panic boost when very close
  if dist < 30 then speed = speed + 0.4 end

  if dist > 0.01 then
    local nx = dx / dist
    local ny = dy / dist
    -- jitter so it isn't a straight line
    local jitter = math.sin(time() / 180 + baby.x * 0.07) * 0.6
    local px = -ny
    local py = nx
    baby.vx = nx * speed + px * jitter
    baby.vy = ny * speed + py * jitter
  end

  -- bounce off play area edges by steering inward
  if baby.x < 10 then baby.vx = baby.vx + 0.6 end
  if baby.x > SW - 11 then baby.vx = baby.vx - 0.6 end
  if baby.y < PLAY_TOP + 8 then baby.vy = baby.vy + 0.6 end
  if baby.y > PLAY_BOTTOM - 8 then baby.vy = baby.vy - 0.6 end

  baby.x = baby.x + baby.vx
  baby.y = baby.y + baby.vy
  baby.x = clamp(baby.x, 4, SW - 5)
  baby.y = clamp(baby.y, PLAY_TOP + 4, PLAY_BOTTOM - 4)
  if baby.vx > 0.1 then baby.facing = 1
  elseif baby.vx < -0.1 then baby.facing = -1 end
  baby.wiggle = baby.wiggle + math.abs(baby.vx) + math.abs(baby.vy)

  -- catch check
  if dist < CATCH_DIST then
    score = score + 1
    catch_flash = 12
    spawn_hearts(baby.x, baby.y)
    spawn_meow(baby.x, baby.y - 6)
    -- teleport baby to far corner
    teleport_baby()
  end

  -- update particles
  update_hearts()
  update_meows()

  if catch_flash > 0 then catch_flash = catch_flash - 1 end

  -- timer
  time_left = time_left - 1
  if time_left <= 0 then
    time_left = 0
    if score > high_score then high_score = score end
    state = "over"
  end
end

function update_over()
  update_hearts()
  update_meows()
  if btnp(4) then init_game() end
end

function teleport_baby()
  -- pick a spot far from cow
  local best_x, best_y = baby.x, baby.y
  local best_d = -1
  for i = 1, 8 do
    local tx = 10 + math.random() * (SW - 20)
    local ty = PLAY_TOP + 6 + math.random() * (PLAY_BOTTOM - PLAY_TOP - 12)
    local dx = tx - cow.x
    local dy = ty - cow.y
    local d = dx * dx + dy * dy
    if d > best_d then
      best_d = d
      best_x = tx
      best_y = ty
    end
  end
  baby.x = best_x
  baby.y = best_y
  baby.vx = 0
  baby.vy = 0
end

function spawn_hearts(x, y)
  for i = 1, 5 do
    table.insert(hearts, {
      x = x + (math.random() - 0.5) * 6,
      y = y + (math.random() - 0.5) * 6,
      vx = (math.random() - 0.5) * 1.6,
      vy = -0.6 - math.random() * 1.0,
      life = 30 + math.random(0, 12),
    })
  end
end

function update_hearts()
  for i = #hearts, 1, -1 do
    local h = hearts[i]
    h.x = h.x + h.vx
    h.y = h.y + h.vy
    h.vy = h.vy + 0.05
    h.life = h.life - 1
    if h.life <= 0 then table.remove(hearts, i) end
  end
end

function spawn_meow(x, y)
  table.insert(meows, {x = x, y = y, life = 40})
end

function update_meows()
  for i = #meows, 1, -1 do
    local m = meows[i]
    m.y = m.y - 0.4
    m.life = m.life - 1
    if m.life <= 0 then table.remove(meows, i) end
  end
end

function clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

-- drawing

function draw_grass()
  -- background
  cls(3)  -- dark green
  -- lighter grass tufts
  for i = 0, 24 do
    local gx = (i * 41 + 17) % SW
    local gy = PLAY_TOP + 2 + (i * 23) % (PLAY_BOTTOM - PLAY_TOP - 4)
    pix(gx, gy, 6)
    pix(gx + 1, gy + 1, 6)
    pix(gx - 1, gy + 1, 6)
  end
  -- subtle flowers
  for i = 0, 6 do
    local fx = (i * 67 + 23) % (SW - 8) + 4
    local fy = PLAY_TOP + 6 + (i * 31) % (PLAY_BOTTOM - PLAY_TOP - 16)
    pix(fx, fy, 12)
    pix(fx + 1, fy, 12)
    pix(fx, fy + 1, 12)
    pix(fx + 1, fy + 1, 12)
    pix(fx + 1, fy + 1, 4)  -- yellow center
  end
  -- play area frame
  rectb(0, PLAY_TOP - 1, SW, PLAY_BOTTOM - PLAY_TOP + 2, 0)
end

-- draw cow cat: white body with black spots
function draw_cow_cat(x, y, facing)
  local fx = math.floor(x)
  local fy = math.floor(y)
  local f = facing or 1
  -- body (white)
  rect(fx - 4, fy - 2, 9, 6, 12)
  -- head
  rect(fx - 1 + (f * 3), fy - 5, 5, 5, 12)
  -- ears
  pix(fx - 1 + (f * 3), fy - 6, 12)
  pix(fx + 3 * f + 2, fy - 6, 12)
  -- legs
  rect(fx - 3, fy + 4, 2, 2, 12)
  rect(fx + 2, fy + 4, 2, 2, 12)
  -- tail
  rect(fx - 5 - (f == 1 and 1 or -8), fy - 1, 2, 2, 12)
  -- black cow spots on body
  pix(fx - 2, fy - 1, 0)
  pix(fx - 1, fy - 1, 0)
  pix(fx - 2, fy, 0)
  pix(fx + 2, fy + 1, 0)
  pix(fx + 3, fy + 1, 0)
  pix(fx + 3, fy + 2, 0)
  pix(fx, fy + 2, 0)
  -- spot on head
  pix(fx + (f * 3), fy - 4, 0)
  pix(fx + (f * 3) + 1, fy - 4, 0)
  -- eye
  pix(fx + (f * 3) + (f == 1 and 3 or 1), fy - 3, 0)
  -- nose (pink)
  pix(fx + (f * 3) + (f == 1 and 4 or 0), fy - 2, 2)
end

-- draw baby cat: small orange tabby
function draw_baby_cat(x, y, facing, wiggle)
  local fx = math.floor(x)
  local fy = math.floor(y)
  local f = facing or 1
  local bob = math.floor(math.sin(wiggle * 0.15) * 1)
  -- body (orange)
  rect(fx - 2, fy - 1 + bob, 6, 4, 4)
  -- head
  rect(fx - 1 + (f * 2), fy - 3 + bob, 4, 4, 4)
  -- ears (triangles)
  pix(fx - 1 + (f * 2), fy - 4 + bob, 4)
  pix(fx + 2 * f + 1, fy - 4 + bob, 4)
  -- darker tabby stripes
  pix(fx - 1, fy + bob, 2)
  pix(fx + 1, fy + bob, 2)
  pix(fx + 3, fy + bob, 2)
  pix(fx + (f * 2), fy - 2 + bob, 2)
  -- legs
  pix(fx - 1, fy + 3 + bob, 4)
  pix(fx + 2, fy + 3 + bob, 4)
  -- tail (curled, animated)
  local twirl = math.floor(math.sin(wiggle * 0.2) * 1)
  pix(fx - 3 - (f == 1 and 0 or -6), fy + bob + twirl, 4)
  pix(fx - 4 - (f == 1 and 0 or -8), fy - 1 + bob + twirl, 4)
  -- eye (big sparkle)
  pix(fx + (f * 2) + (f == 1 and 2 or 1), fy - 2 + bob, 0)
  -- pink nose
  pix(fx + (f * 2) + (f == 1 and 3 or 0), fy - 1 + bob, 14)
end

function draw_heart(x, y, c)
  local fx = math.floor(x)
  local fy = math.floor(y)
  pix(fx, fy, c)
  pix(fx + 2, fy, c)
  pix(fx - 1, fy + 1, c)
  pix(fx, fy + 1, c)
  pix(fx + 1, fy + 1, c)
  pix(fx + 2, fy + 1, c)
  pix(fx + 3, fy + 1, c)
  pix(fx, fy + 2, c)
  pix(fx + 1, fy + 2, c)
  pix(fx + 2, fy + 2, c)
  pix(fx + 1, fy + 3, c)
end

function draw_game()
  draw_grass()

  -- shadows under cats
  circ(math.floor(cow.x), math.floor(cow.y) + 6, 4, 0)
  circ(math.floor(baby.x), math.floor(baby.y) + 4, 3, 0)

  -- meows
  for _, m in ipairs(meows) do
    print("meow!", math.floor(m.x) - 8, math.floor(m.y), 14, false, 1, true)
  end

  -- baby cat
  draw_baby_cat(baby.x, baby.y, baby.facing, baby.wiggle)

  -- cow cat (flashes pink when catching)
  draw_cow_cat(cow.x, cow.y, cow.facing)
  if catch_flash > 0 and catch_flash % 4 < 2 then
    circb(math.floor(cow.x), math.floor(cow.y), 8, 14)
  end

  -- hearts
  for _, h in ipairs(hearts) do
    local c = (h.life > 10) and 2 or 14
    draw_heart(h.x, h.y, c)
  end

  -- HUD
  rect(0, 0, SW, 9, 0)
  print("CATCHES:" .. score, 2, 1, 12, false, 1, true)
  local secs = math.ceil(time_left / 60)
  local tcol = (secs <= 10 and (math.floor(time() / 200) % 2 == 0)) and 2 or 4
  print("TIME:" .. secs, 100, 1, tcol, false, 1, true)
  print("HI:" .. high_score, 190, 1, 14, false, 1, true)
end

function draw_title()
  cls(1)
  -- starry / dot background
  for i = 0, 80 do
    local sx = (i * 37) % SW
    local sy = (i * 53) % SH
    pix(sx, sy, 2 + (i % 3))
  end

  -- title text
  print("COW CAT CHASE", 50, 22, 12, false, 2, true)
  print("COW CAT CHASE", 51, 22, 14, false, 2, true)

  -- demo cats animating across
  local t = time() / 30
  local bx = 60 + (t % 120)
  local cx = bx - 30 - math.sin(t * 0.05) * 4
  draw_baby_cat(bx, 64, 1, t)
  draw_cow_cat(cx, 64, 1)
  -- little chase dust
  for i = 0, 3 do
    pix(math.floor(cx) - 6 - i * 2, 68 + (i % 2), 13)
  end

  print("Catch the baby cat!", 60, 88, 12, false, 1, true)
  print("Arrow keys to move", 64, 100, 14, false, 1, true)

  if math.floor(time() / 400) % 2 == 0 then
    print("PRESS Z TO START", 64, 116, 4, false, 1, true)
  end
end

function draw_over_overlay()
  rect(40, 36, 160, 64, 0)
  rectb(40, 36, 160, 64, 12)
  rectb(41, 37, 158, 62, 14)

  print("TIME UP!", 92, 44, 2, false, 1, true)
  print("Catches: " .. score, 86, 60, 12, false, 1, true)
  if score > 0 and score >= high_score then
    print("NEW BEST!", 90, 72, 4, false, 1, true)
  else
    print("Best: " .. high_score, 90, 72, 14, false, 1, true)
  end
  if math.floor(time() / 400) % 2 == 0 then
    print("Press Z to play again", 60, 88, 12, false, 1, true)
  end
end
