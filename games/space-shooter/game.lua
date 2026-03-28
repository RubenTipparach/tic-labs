-- title:  Void Patrol
-- author: tic-labs
-- desc:   Space shooter - survive the alien waves
-- script: lua

-- player
local player = {
  x = 112, y = 110,
  w = 8, h = 8,
  speed = 2,
  alive = true,
  iframes = 0,   -- invincibility frames
  lives = 3,
  bombs = 3,
  fire_cd = 0,
  fire_rate = 6,
}

-- game objects
local bullets = {}
local enemies = {}
local particles = {}
local stars = {}
local powerups = {}

-- game state
local score = 0
local high_score = 0
local wave = 1
local wave_timer = 0
local wave_delay = 120
local enemies_to_spawn = 0
local spawn_timer = 0
local state = "title"  -- title, playing, dead
local dead_timer = 0
local shake = 0
local bomb_flash = 0

-- enemy types
local ENEMY_TYPES = {
  -- basic: drifts down, no shooting
  {hp=1, speed=0.8, score=10, color=2, w=6, h=6, pattern="drift"},
  -- zigzag: moves side to side
  {hp=1, speed=1.0, score=15, color=8, w=6, h=6, pattern="zigzag"},
  -- tank: slower, more HP
  {hp=3, speed=0.4, score=30, color=6, w=8, h=8, pattern="drift"},
  -- dive: fast, dives at player
  {hp=1, speed=1.8, score=20, color=9, w=5, h=5, pattern="dive"},
  -- shooter: fires back
  {hp=2, speed=0.5, score=25, color=3, w=7, h=7, pattern="shoot"},
}

-- init stars
for i = 1, 60 do
  stars[i] = {
    x = math.random(0, 239),
    y = math.random(0, 135),
    s = math.random(1, 3),  -- speed layer
  }
end

function spawn_particle(x, y, color, count, spread, life)
  for i = 1, (count or 4) do
    local angle = math.random() * math.pi * 2
    local spd = math.random() * (spread or 2) + 0.5
    table.insert(particles, {
      x = x, y = y,
      vx = math.cos(angle) * spd,
      vy = math.sin(angle) * spd,
      life = (life or 15) + math.random(0, 8),
      color = color,
    })
  end
end

function spawn_enemy(etype_idx)
  local et = ENEMY_TYPES[etype_idx]
  local e = {
    x = math.random(8, 232 - et.w),
    y = -et.h,
    vx = 0,
    vy = et.speed,
    hp = et.hp,
    max_hp = et.hp,
    score = et.score,
    color = et.color,
    w = et.w,
    h = et.h,
    pattern = et.pattern,
    timer = math.random(0, 60),
    fire_cd = 0,
    start_x = 0,
  }
  e.start_x = e.x
  table.insert(enemies, e)
end

function start_wave()
  wave_timer = 0
  -- more enemies each wave, introduce new types
  local count = 3 + wave * 2
  if count > 20 then count = 20 end
  enemies_to_spawn = count
  spawn_timer = 0
end

function fire_bullet(x, y)
  table.insert(bullets, {
    x = x, y = y,
    vy = -4,
    friendly = true,
  })
end

function fire_enemy_bullet(x, y)
  -- aim roughly toward player
  local dx = player.x - x
  local dy = player.y - y
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < 1 then dist = 1 end
  local spd = 1.5
  table.insert(bullets, {
    x = x, y = y,
    vx = (dx / dist) * spd,
    vy = (dy / dist) * spd,
    friendly = false,
  })
end

function use_bomb()
  if player.bombs <= 0 then return end
  player.bombs = player.bombs - 1
  bomb_flash = 8
  shake = 6
  -- destroy all enemies on screen
  for _, e in ipairs(enemies) do
    score = score + e.score
    spawn_particle(e.x + e.w / 2, e.y + e.h / 2, e.color, 8, 3, 20)
  end
  enemies = {}
  -- destroy all enemy bullets
  local kept = {}
  for _, b in ipairs(bullets) do
    if b.friendly then table.insert(kept, b) end
  end
  bullets = kept
end

function init_game()
  player.x = 112
  player.y = 110
  player.alive = true
  player.iframes = 0
  player.lives = 3
  player.bombs = 3
  player.fire_cd = 0
  bullets = {}
  enemies = {}
  particles = {}
  powerups = {}
  score = 0
  wave = 1
  wave_timer = 0
  dead_timer = 0
  shake = 0
  bomb_flash = 0
  state = "playing"
  start_wave()
end

function TIC()
  if state == "title" then
    update_stars()
    update_particles()
    draw_title()
    if btnp(4) then init_game() end
  elseif state == "playing" then
    update_game()
    draw_game()
  elseif state == "dead" then
    update_stars()
    update_particles()
    dead_timer = dead_timer + 1
    draw_game()
    draw_dead_overlay()
    if dead_timer > 90 and btnp(4) then init_game() end
  end
end

function update_stars()
  for _, s in ipairs(stars) do
    s.y = s.y + s.s * 0.3
    if s.y > 136 then
      s.y = 0
      s.x = math.random(0, 239)
    end
  end
end

function update_game()
  update_stars()

  -- player input
  if player.alive then
    if btn(0) and player.y > 2 then player.y = player.y - player.speed end
    if btn(1) and player.y < 126 then player.y = player.y + player.speed end
    if btn(2) and player.x > 2 then player.x = player.x - player.speed end
    if btn(3) and player.x < 230 then player.x = player.x + player.speed end

    -- shoot
    player.fire_cd = player.fire_cd - 1
    if btn(4) and player.fire_cd <= 0 then
      fire_bullet(player.x + 3, player.y - 2)
      player.fire_cd = player.fire_rate
      spawn_particle(player.x + 4, player.y - 1, 12, 2, 0.8, 5)
    end

    -- bomb
    if btnp(5) then use_bomb() end

    -- iframes countdown
    if player.iframes > 0 then
      player.iframes = player.iframes - 1
    end
  end

  -- update bullets
  local kept_bullets = {}
  for _, b in ipairs(bullets) do
    b.x = b.x + (b.vx or 0)
    b.y = b.y + b.vy
    if b.y > -4 and b.y < 140 and b.x > -4 and b.x < 244 then
      table.insert(kept_bullets, b)
    end
  end
  bullets = kept_bullets

  -- update enemies
  local kept_enemies = {}
  for _, e in ipairs(enemies) do
    e.timer = e.timer + 1

    if e.pattern == "zigzag" then
      e.x = e.start_x + math.sin(e.timer * 0.05) * 30
      e.y = e.y + e.vy
    elseif e.pattern == "dive" then
      if e.y > 40 then
        -- dive toward player
        local dx = player.x - e.x
        if math.abs(dx) > 2 then
          e.x = e.x + (dx > 0 and 1 or -1) * 0.8
        end
        e.vy = e.vy + 0.02
      end
      e.y = e.y + e.vy
    elseif e.pattern == "shoot" then
      e.y = e.y + e.vy
      -- stop at y=30-50 and shoot
      if e.y > 30 then
        e.vy = 0
        e.fire_cd = e.fire_cd - 1
        if e.fire_cd <= 0 then
          fire_enemy_bullet(e.x + e.w / 2, e.y + e.h)
          e.fire_cd = 60 + math.random(0, 30)
        end
      end
    else
      e.y = e.y + e.vy
    end

    -- keep if on screen
    if e.y < 145 and e.y > -20 then
      table.insert(kept_enemies, e)
    end
  end
  enemies = kept_enemies

  -- bullet-enemy collision
  for bi = #bullets, 1, -1 do
    local b = bullets[bi]
    if b.friendly then
      for ei = #enemies, 1, -1 do
        local e = enemies[ei]
        if b.x >= e.x and b.x <= e.x + e.w and
           b.y >= e.y and b.y <= e.y + e.h then
          e.hp = e.hp - 1
          table.remove(bullets, bi)
          if e.hp <= 0 then
            score = score + e.score
            spawn_particle(e.x + e.w/2, e.y + e.h/2, e.color, 6, 2.5, 18)
            spawn_particle(e.x + e.w/2, e.y + e.h/2, 4, 4, 1.5, 12)
            shake = 2
            -- chance to drop powerup
            if math.random() < 0.15 then
              local kind = math.random(1, 2)  -- 1=life 2=bomb
              table.insert(powerups, {
                x = e.x, y = e.y,
                vy = 0.5,
                kind = kind,
              })
            end
            table.remove(enemies, ei)
          else
            spawn_particle(b.x, b.y, 12, 2, 1, 6)
          end
          break
        end
      end
    end
  end

  -- enemy bullet-player collision
  if player.alive and player.iframes <= 0 then
    for bi = #bullets, 1, -1 do
      local b = bullets[bi]
      if not b.friendly then
        if b.x >= player.x and b.x <= player.x + player.w and
           b.y >= player.y and b.y <= player.y + player.h then
          player_hit()
          table.remove(bullets, bi)
          break
        end
      end
    end

    -- enemy-player collision
    for ei = #enemies, 1, -1 do
      local e = enemies[ei]
      if player.x + player.w > e.x and player.x < e.x + e.w and
         player.y + player.h > e.y and player.y < e.y + e.h then
        player_hit()
        e.hp = e.hp - 1
        if e.hp <= 0 then
          score = score + e.score
          spawn_particle(e.x + e.w/2, e.y + e.h/2, e.color, 6, 2, 15)
          table.remove(enemies, ei)
        end
        break
      end
    end
  end

  -- update powerups
  local kept_pu = {}
  for _, p in ipairs(powerups) do
    p.y = p.y + p.vy
    -- collect
    if player.alive and
       p.x + 6 > player.x and p.x < player.x + player.w and
       p.y + 6 > player.y and p.y < player.y + player.h then
      if p.kind == 1 then
        player.lives = player.lives + 1
      else
        player.bombs = player.bombs + 1
      end
      spawn_particle(p.x + 3, p.y + 3, 11, 6, 2, 12)
    elseif p.y < 140 then
      table.insert(kept_pu, p)
    end
  end
  powerups = kept_pu

  -- update particles
  update_particles()

  -- shake decay
  if shake > 0 then shake = shake - 0.5 end
  if shake < 0 then shake = 0 end

  -- bomb flash decay
  if bomb_flash > 0 then bomb_flash = bomb_flash - 1 end

  -- wave spawning
  if enemies_to_spawn > 0 then
    spawn_timer = spawn_timer + 1
    if spawn_timer >= 20 then
      spawn_timer = 0
      -- pick enemy type based on wave
      local max_type = math.min(wave, #ENEMY_TYPES)
      local t = math.random(1, max_type)
      spawn_enemy(t)
      enemies_to_spawn = enemies_to_spawn - 1
    end
  elseif #enemies == 0 then
    -- wave cleared
    wave_timer = wave_timer + 1
    if wave_timer >= wave_delay then
      wave = wave + 1
      start_wave()
    end
  end
end

function player_hit()
  player.lives = player.lives - 1
  player.iframes = 90  -- 1.5 seconds
  shake = 4
  spawn_particle(player.x + 4, player.y + 4, 2, 8, 2, 15)
  spawn_particle(player.x + 4, player.y + 4, 4, 4, 1.5, 10)
  if player.lives <= 0 then
    player.alive = false
    state = "dead"
    dead_timer = 0
    spawn_particle(player.x + 4, player.y + 4, 12, 12, 3, 25)
    spawn_particle(player.x + 4, player.y + 4, 2, 8, 2.5, 20)
    if score > high_score then high_score = score end
  end
end

function update_particles()
  local kept = {}
  for _, p in ipairs(particles) do
    p.x = p.x + p.vx
    p.y = p.y + p.vy
    p.life = p.life - 1
    p.vx = p.vx * 0.95
    p.vy = p.vy * 0.95
    if p.life > 0 then
      table.insert(kept, p)
    end
  end
  particles = kept
end

-- DRAWING

function draw_game()
  local sx = 0
  local sy = 0
  if shake > 0 then
    sx = math.random(-1, 1) * math.ceil(shake)
    sy = math.random(-1, 1) * math.ceil(shake)
  end

  cls(0)

  -- bomb flash
  if bomb_flash > 0 then
    cls(bomb_flash > 4 and 12 or 1)
  end

  -- stars
  for _, s in ipairs(stars) do
    local c = 1
    if s.s == 2 then c = 13 end
    if s.s == 3 then c = 15 end
    pix(s.x + sx, s.y + sy, c)
  end

  -- powerups
  for _, p in ipairs(powerups) do
    local px = p.x + sx
    local py = p.y + sy
    if p.kind == 1 then
      -- life (heart shape - red)
      rect(px, py + 1, 6, 4, 2)
      rect(px + 1, py, 2, 1, 2)
      rect(px + 3, py, 2, 1, 2)
      pix(px, py + 5, 2)
      pix(px + 5, py + 5, 2)
      pix(px + 1, py + 5, 2)
      pix(px + 4, py + 5, 2)
      pix(px + 2, py + 6, 2)
      pix(px + 3, py + 6, 2)
    else
      -- bomb (circle)
      circ(px + 3, py + 3, 3, 4)
      pix(px + 3, py - 1, 3)
    end
  end

  -- enemies
  for _, e in ipairs(enemies) do
    local ex = e.x + sx
    local ey = e.y + sy
    -- body
    rect(ex, ey + 1, e.w, e.h - 2, e.color)
    rect(ex + 1, ey, e.w - 2, e.h, e.color)
    -- highlight
    pix(ex + 2, ey + 1, e.color + 1)
    -- damage flash
    if e.hp < e.max_hp then
      pix(ex + e.w - 2, ey + 1, 12)
    end
  end

  -- player
  if player.alive then
    local px = player.x + sx
    local py = player.y + sy
    -- blink during iframes
    if player.iframes <= 0 or math.floor(time() / 50) % 2 == 0 then
      -- ship body
      rect(px + 2, py, 4, 8, 12)  -- center column
      rect(px, py + 3, 8, 3, 12)  -- wings
      -- cockpit
      pix(px + 3, py + 1, 11)
      pix(px + 4, py + 1, 11)
      -- wing tips
      pix(px, py + 3, 8)
      pix(px + 7, py + 3, 8)
      -- engine glow
      if math.floor(time() / 80) % 2 == 0 then
        pix(px + 3, py + 8, 3)
        pix(px + 4, py + 8, 2)
      else
        pix(px + 3, py + 8, 2)
        pix(px + 4, py + 8, 3)
      end
    end
  end

  -- bullets
  for _, b in ipairs(bullets) do
    local bx = b.x + sx
    local by = b.y + sy
    if b.friendly then
      rect(bx, by, 2, 4, 12)
      pix(bx, by, 11)
      pix(bx + 1, by, 11)
    else
      circ(bx, by, 1, 2)
      pix(bx, by, 4)
    end
  end

  -- particles
  for _, p in ipairs(particles) do
    if p.life > 3 then
      pix(p.x + sx, p.y + sy, p.color)
    end
  end

  -- HUD
  draw_hud(sx, sy)
end

function draw_hud()
  -- score
  print("SCORE " .. score, 4, 1, 12, false, 1, false)
  -- wave
  print("WAVE " .. wave, 100, 1, 15, false, 1, false)
  -- lives
  for i = 1, player.lives do
    local lx = 230 - (i - 1) * 8
    rect(lx + 1, 1, 3, 5, 2)
    rect(lx, 2, 5, 3, 2)
  end
  -- bombs
  for i = 1, player.bombs do
    circ(178 + (i - 1) * 7, 3, 2, 4)
  end

  -- wave cleared message
  if enemies_to_spawn <= 0 and #enemies == 0 and state == "playing" then
    if wave_timer < 60 then
      print("WAVE " .. (wave) .. " CLEAR!", 80, 60, 11, false, 1, true)
    end
  end
end

function draw_title()
  cls(0)

  -- stars
  for _, s in ipairs(stars) do
    local c = 1
    if s.s == 2 then c = 13 end
    if s.s == 3 then c = 15 end
    pix(s.x, s.y, c)
  end

  -- particles (title explosions)
  for _, p in ipairs(particles) do
    if p.life > 3 then
      pix(p.x, p.y, p.color)
    end
  end

  -- spawn random title explosions
  if math.random() < 0.03 then
    spawn_particle(
      math.random(20, 220), math.random(20, 80),
      math.random(2, 6), 8, 2, 20
    )
  end

  -- title
  print("VOID", 72, 24, 12, false, 3, true)
  print("PATROL", 63, 46, 8, false, 3, true)

  -- instructions
  print("ARROWS: MOVE", 76, 80, 15, false, 1, true)
  print("Z: SHOOT  X: BOMB", 60, 92, 15, false, 1, true)

  -- high score
  if high_score > 0 then
    print("HI-SCORE: " .. high_score, 72, 108, 4, false, 1, true)
  end

  -- blinking start
  if math.floor(time() / 500) % 2 == 0 then
    print("PRESS Z TO START", 64, 120, 11, false, 1, true)
  end
end

function draw_dead_overlay()
  rect(40, 38, 160, 60, 0)
  rectb(40, 38, 160, 60, 2)

  print("SHIP DESTROYED", 68, 44, 2, false, 1, true)
  print("Score: " .. score, 88, 58, 12, false, 1, true)
  print("Wave: " .. wave, 92, 68, 15, false, 1, true)

  if score >= high_score and score > 0 then
    print("NEW HIGH SCORE!", 68, 78, 4, false, 1, true)
  end

  if dead_timer > 90 then
    if math.floor(time() / 400) % 2 == 0 then
      print("Press Z to retry", 68, 88, 15, false, 1, true)
    end
  end
end
