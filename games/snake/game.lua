-- title:  Snake
-- author: tic-labs
-- desc:   Classic snake game
-- script: lua

-- grid config (TIC-80 screen: 240x136)
local CELL = 8
local COLS = 30  -- 240/8
local ROWS = 16  -- 128/8 (top 8px reserved for HUD)
local OX = 0
local OY = 8     -- offset for HUD

-- directions: 0=right 1=down 2=left 3=up
local DX = {1, 0, -1, 0}
local DY = {0, 1, 0, -1}

-- game state
local snake = {}
local dir = 0
local next_dir = 0
local food = {x = 0, y = 0}
local score = 0
local high_score = 0
local state = "title"  -- title, playing, dead
local tick = 0
local speed = 6  -- frames per move (lower = faster)
local grow = 0
local dead_timer = 0

function place_food()
  local attempts = 0
  while attempts < 500 do
    local fx = math.random(0, COLS - 1)
    local fy = math.random(0, ROWS - 1)
    local on_snake = false
    for _, seg in ipairs(snake) do
      if seg.x == fx and seg.y == fy then
        on_snake = true
        break
      end
    end
    if not on_snake then
      food.x = fx
      food.y = fy
      return
    end
    attempts = attempts + 1
  end
end

function init_game()
  snake = {}
  local sx = math.floor(COLS / 2)
  local sy = math.floor(ROWS / 2)
  for i = 0, 3 do
    table.insert(snake, {x = sx - i, y = sy})
  end
  dir = 0
  next_dir = 0
  score = 0
  speed = 6
  grow = 0
  tick = 0
  dead_timer = 0
  state = "playing"
  place_food()
end

function TIC()
  if state == "title" then
    update_title()
    draw_title()
  elseif state == "playing" then
    update_game()
    draw_game()
  elseif state == "dead" then
    update_dead()
    draw_game()
    draw_dead_overlay()
  end
end

function update_title()
  if btnp(4) then  -- Z
    init_game()
  end
end

function update_game()
  -- input (prevent 180-degree reversal)
  if btnp(0) and dir ~= 1 then next_dir = 3 end  -- up
  if btnp(1) and dir ~= 3 then next_dir = 1 end  -- down
  if btnp(2) and dir ~= 0 then next_dir = 2 end  -- left
  if btnp(3) and dir ~= 2 then next_dir = 0 end  -- right

  tick = tick + 1
  if tick < speed then return end
  tick = 0

  dir = next_dir

  -- new head position
  local head = snake[1]
  local nx = head.x + DX[dir + 1]
  local ny = head.y + DY[dir + 1]

  -- wall collision
  if nx < 0 or nx >= COLS or ny < 0 or ny >= ROWS then
    die()
    return
  end

  -- self collision
  for i, seg in ipairs(snake) do
    if seg.x == nx and seg.y == ny then
      die()
      return
    end
  end

  -- insert new head
  table.insert(snake, 1, {x = nx, y = ny})

  -- check food
  if nx == food.x and ny == food.y then
    score = score + 10
    grow = grow + 1
    -- speed up every 50 points
    if score % 50 == 0 and speed > 2 then
      speed = speed - 1
    end
    place_food()
  end

  -- remove tail (unless growing)
  if grow > 0 then
    grow = grow - 1
  else
    table.remove(snake)
  end
end

function die()
  state = "dead"
  dead_timer = 0
  if score > high_score then
    high_score = score
  end
end

function update_dead()
  dead_timer = dead_timer + 1
  if dead_timer > 60 and btnp(4) then  -- Z after 1 second
    init_game()
  end
end

-- drawing

function draw_cell(cx, cy, color)
  local px = OX + cx * CELL
  local py = OY + cy * CELL
  rect(px + 1, py + 1, CELL - 2, CELL - 2, color)
end

function draw_game()
  cls(0)

  -- grid dots (subtle)
  for gx = 0, COLS - 1 do
    for gy = 0, ROWS - 1 do
      pix(OX + gx * CELL, OY + gy * CELL, 1)
    end
  end

  -- border
  rectb(OX, OY, COLS * CELL, ROWS * CELL, 1)

  -- food (pulsing)
  local pulse = math.floor(time() / 150) % 2
  local food_color = pulse == 0 and 6 or 2
  local fpx = OX + food.x * CELL
  local fpy = OY + food.y * CELL
  rect(fpx + 1, fpy + 1, CELL - 2, CELL - 2, food_color)
  -- food sparkle
  if pulse == 0 then
    pix(fpx + 2, fpy + 2, 4)
  end

  -- snake
  for i, seg in ipairs(snake) do
    local color
    if i == 1 then
      color = 11  -- head: bright green
    else
      color = (i % 2 == 0) and 6 or 5  -- alternating body
    end
    draw_cell(seg.x, seg.y, color)
  end

  -- head eyes
  local head = snake[1]
  local hpx = OX + head.x * CELL
  local hpy = OY + head.y * CELL
  if dir == 0 then      -- right
    pix(hpx + 5, hpy + 2, 0)
    pix(hpx + 5, hpy + 5, 0)
  elseif dir == 1 then  -- down
    pix(hpx + 2, hpy + 5, 0)
    pix(hpx + 5, hpy + 5, 0)
  elseif dir == 2 then  -- left
    pix(hpx + 2, hpy + 2, 0)
    pix(hpx + 2, hpy + 5, 0)
  else                  -- up
    pix(hpx + 2, hpy + 2, 0)
    pix(hpx + 5, hpy + 2, 0)
  end

  -- HUD
  print("SCORE:" .. score, 4, 1, 11, false, 1, false)
  print("HI:" .. high_score, 180, 1, 15, false, 1, false)
  print("LEN:" .. #snake, 90, 1, 6, false, 1, false)
end

function draw_title()
  cls(0)

  -- starfield
  for i = 0, 60 do
    local sx = (i * 37 + math.floor(time() / 50)) % 240
    local sy = (i * 53) % 136
    pix(sx, sy, 1 + (i % 3))
  end

  -- title
  print("SNAKE", 88, 30, 11, false, 2, true)

  -- animated snake
  local t = math.floor(time() / 200)
  for i = 0, 7 do
    local sx = 80 + i * 10
    local sy = 60 + math.floor(math.sin((t + i) * 0.8) * 6)
    local c = (i == 0) and 11 or ((i % 2 == 0) and 6 or 5)
    rect(sx, sy, 8, 8, c)
  end

  -- instructions
  print("ARROW KEYS TO MOVE", 60, 90, 15, false, 1, true)
  print("PRESS Z TO START", 68, 105, 12, false, 1, true)

  -- blinking prompt
  if math.floor(time() / 500) % 2 == 0 then
    print("> START <", 84, 120, 6, false, 1, true)
  end
end

function draw_dead_overlay()
  -- darken background
  rect(50, 40, 140, 56, 0)
  rectb(50, 40, 140, 56, 2)

  print("GAME OVER!", 78, 48, 2, false, 1, true)
  print("Score: " .. score, 88, 62, 11, false, 1, true)

  if score >= high_score and score > 0 then
    print("NEW HIGH SCORE!", 68, 72, 4, false, 1, true)
  end

  if dead_timer > 60 then
    if math.floor(time() / 400) % 2 == 0 then
      print("Press Z to retry", 68, 84, 15, false, 1, true)
    end
  end
end
