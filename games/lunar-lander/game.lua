-- title:  Lunar Lander
-- author: tic-labs
-- desc:   Land the lunar module safely on the landing pad
-- script: lua

-- game state
local ship = {
  x = 120, y = 20,
  vx = 0.3, vy = 0,
  fuel = 100,
  angle = 0,
  thrust = false,
  alive = true,
  landed = false
}

local GRAVITY = 0.012
local THRUST_POWER = 0.035
local ROTATE_SPEED = 3
local MAX_LAND_VY = 0.6
local MAX_LAND_VX = 0.4

-- terrain
local terrain = {}
local pad_x = 0
local pad_w = 24

local stars = {}

local state = "playing" -- playing, landed, crashed
local msg_timer = 0

function init()
  -- generate starfield
  stars = {}
  for i = 1, 40 do
    stars[i] = {
      x = math.random(0, 239),
      y = math.random(0, 100),
      b = math.random(1, 3)
    }
  end

  -- generate terrain
  terrain = {}
  local segments = 20
  local seg_w = 240 / segments

  -- pick a random landing pad position
  local pad_seg = math.random(4, segments - 4)
  pad_x = (pad_seg - 1) * seg_w

  for i = 0, segments do
    local tx = i * seg_w
    local ty
    if i == pad_seg or i == pad_seg + 1 then
      -- flat landing pad
      ty = 105
    else
      ty = 95 + math.random(0, 25)
    end
    table.insert(terrain, {x = tx, y = ty})
  end

  -- reset ship
  ship.x = math.random(40, 200)
  ship.y = 20
  ship.vx = (math.random() - 0.5) * 0.6
  ship.vy = 0
  ship.fuel = 100
  ship.angle = 0
  ship.thrust = false
  ship.alive = true
  ship.landed = false
  state = "playing"
  msg_timer = 0
end

init()

function get_terrain_y(px)
  -- interpolate terrain height at position px
  for i = 1, #terrain - 1 do
    local t1 = terrain[i]
    local t2 = terrain[i + 1]
    if px >= t1.x and px <= t2.x then
      local frac = (px - t1.x) / (t2.x - t1.x)
      return t1.y + (t2.y - t1.y) * frac
    end
  end
  return 136
end

function TIC()
  if state == "playing" then
    update_playing()
  else
    msg_timer = msg_timer + 1
    if msg_timer > 180 or btnp(4) then
      init()
    end
  end

  draw()
end

function update_playing()
  ship.thrust = false

  -- rotate
  if btn(2) then ship.angle = ship.angle - ROTATE_SPEED end
  if btn(3) then ship.angle = ship.angle + ROTATE_SPEED end

  -- thrust
  if btn(4) and ship.fuel > 0 then
    local rad = math.rad(ship.angle - 90)
    ship.vx = ship.vx + math.cos(rad) * THRUST_POWER
    ship.vy = ship.vy + math.sin(rad) * THRUST_POWER
    ship.fuel = ship.fuel - 0.3
    ship.thrust = true
    if ship.fuel < 0 then ship.fuel = 0 end
  end

  -- gravity
  ship.vy = ship.vy + GRAVITY

  -- move
  ship.x = ship.x + ship.vx
  ship.y = ship.y + ship.vy

  -- wrap horizontal
  if ship.x < 0 then ship.x = 240 end
  if ship.x > 240 then ship.x = 0 end

  -- check ground collision
  local ground_y = get_terrain_y(ship.x)
  if ship.y + 4 >= ground_y then
    ship.y = ground_y - 4
    -- check if on landing pad
    local on_pad = ship.x >= pad_x and ship.x <= pad_x + pad_w
    local safe_vy = math.abs(ship.vy) < MAX_LAND_VY
    local safe_vx = math.abs(ship.vx) < MAX_LAND_VX
    local safe_angle = math.abs(ship.angle % 360) < 15 or math.abs(ship.angle % 360) > 345

    if on_pad and safe_vy and safe_vx and safe_angle then
      state = "landed"
      ship.landed = true
    else
      state = "crashed"
      ship.alive = false
    end
    ship.vx = 0
    ship.vy = 0
  end

  -- ceiling
  if ship.y < 0 then
    ship.y = 0
    ship.vy = 0
  end
end

function draw()
  cls(0)

  -- stars
  for _, s in ipairs(stars) do
    pix(s.x, s.y, 12 + s.b)
  end

  -- terrain
  for i = 1, #terrain - 1 do
    local t1 = terrain[i]
    local t2 = terrain[i + 1]
    -- fill terrain
    for x = math.floor(t1.x), math.floor(t2.x) do
      local frac = (x - t1.x) / (t2.x - t1.x)
      local y = math.floor(t1.y + (t2.y - t1.y) * frac)
      line(x, y, x, 136, 4)
    end
    line(t1.x, t1.y, t2.x, t2.y, 6)
  end

  -- landing pad
  rect(pad_x, 103, pad_w, 3, 11)

  -- landing pad markers
  line(pad_x, 100, pad_x, 103, 11)
  line(pad_x + pad_w, 100, pad_x + pad_w, 103, 11)

  -- ship
  draw_ship()

  -- HUD
  draw_hud()

  -- messages
  if state == "landed" then
    local score = math.floor(ship.fuel * 10)
    print("LANDED SAFELY!", 75, 50, 11, false, 1, true)
    print("Score: " .. score, 85, 60, 11, false, 1, true)
    print("Press Z to retry", 68, 75, 15, false, 1, true)
  elseif state == "crashed" then
    print("CRASHED!", 90, 50, 2, false, 1, true)
    print("Press Z to retry", 68, 65, 15, false, 1, true)
  end
end

function draw_ship()
  local rad = math.rad(ship.angle)
  local cx, cy = ship.x, ship.y
  local size = 4

  if not ship.alive and state == "crashed" then
    -- explosion effect
    local t = msg_timer
    if t < 30 then
      for i = 1, 8 do
        local a = (i / 8) * math.pi * 2
        local r = t * 0.8
        local ex = cx + math.cos(a) * r
        local ey = cy + math.sin(a) * r
        circ(ex, ey, 2 - t * 0.05, 2 + (i % 3))
      end
    end
    return
  end

  -- ship body (triangle)
  local cos_a = math.cos(rad)
  local sin_a = math.sin(rad)

  -- nose
  local nx = cx + sin_a * (-size)
  local ny = cy + cos_a * (size)

  -- left wing
  local lx = cx + cos_a * (-size * 0.7) + sin_a * (size * 0.5)
  local ly = cy + sin_a * (size * 0.7) + cos_a * (-size * 0.5)

  -- right wing
  local rx = cx + cos_a * (size * 0.7) + sin_a * (size * 0.5)
  local ry = cy + sin_a * (-size * 0.7) + cos_a * (-size * 0.5)

  tri(nx, ny, lx, ly, rx, ry, 12)
  -- outline
  line(nx, ny, lx, ly, 15)
  line(nx, ny, rx, ry, 15)
  line(lx, ly, rx, ry, 15)

  -- thrust flame
  if ship.thrust then
    local fx = cx + sin_a * (size * 0.8)
    local fy = cy + cos_a * (-size * 0.8)
    local fsize = 2 + math.random() * 2
    local flame_rad = math.rad(ship.angle)
    local ffx = fx + math.sin(flame_rad) * fsize
    local ffy = fy - math.cos(flame_rad) * fsize
    line(fx, fy, ffx, ffy, 3)
    pix(ffx, ffy, 2)
  end
end

function draw_hud()
  -- fuel bar background
  rect(4, 4, 52, 6, 1)
  -- fuel bar fill
  local fw = math.floor(ship.fuel * 0.5)
  local fc = 11
  if ship.fuel < 30 then fc = 2 end
  if ship.fuel < 15 then fc = 6 end
  rect(5, 5, fw, 4, fc)
  print("FUEL", 6, 5, 15, false, 1, false)

  -- velocity indicators
  local vx_str = string.format("VX:%.1f", math.abs(ship.vx))
  local vy_str = string.format("VY:%.1f", math.abs(ship.vy))

  local vx_color = math.abs(ship.vx) < MAX_LAND_VX and 11 or 2
  local vy_color = math.abs(ship.vy) < MAX_LAND_VY and 11 or 2

  print(vx_str, 180, 4, vx_color, false, 1, true)
  print(vy_str, 180, 12, vy_color, false, 1, true)

  -- altitude
  local alt = math.floor(get_terrain_y(ship.x) - ship.y - 4)
  if alt < 0 then alt = 0 end
  print("ALT:" .. alt, 180, 20, 15, false, 1, true)

  -- controls hint
  if state == "playing" then
    print("< > ROTATE  Z THRUST", 45, 130, 13, false, 1, true)
  end
end
