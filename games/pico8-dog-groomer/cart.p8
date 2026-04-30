pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- dog groomer (stage 3)
-- by tic-labs

cw=4
cgw=14
cgh=8
cox=64-(cgw*cw)\2
coy=64-(cgh*cw)\2
shift_len=5

function _init()
 best_shift=0
 round=1
 shift_score=0
 state="title"
 particles={}
 wag=0
 cursor={x=64,y=64}
 tools={
  {n="brush",col=14,sfx=0},
  {n="suds", col=12,sfx=1},
  {n="snip", col=6, sfx=2},
  {n="blow", col=10,sfx=3},
 }
 tool=1
 reset_dog()
end

function reset_dog()
 cells={}
 for gy=0,cgh-1 do
  for gx=0,cgw-1 do
   local nx=(gx-(cgw-1)/2)/((cgw-1)/2)
   local ny=(gy-(cgh-1)/2)/((cgh-1)/2)
   if nx*nx+ny*ny<=1.05 then
    add(cells,{gx=gx,gy=gy,tangle=0,dirt=0,fur=0,wet=0})
   end
  end
 end
 local budget=10+round*4
 if budget>56 then budget=56 end
 for i=1,budget do
  local c=cells[1+flr(rnd(#cells))]
  local k=1+flr(rnd(3))
  if k==1 and c.tangle<3 then c.tangle+=1
  elseif k==2 and c.dirt<3 then c.dirt+=1
  elseif k==3 and c.fur<3 then c.fur+=1 end
 end
 start_total=remaining()
 if start_total<1 then start_total=1 end
 dog_time=max(20*60,(42-round*2)*60)
 cursor={x=64,y=64}
 tool=1
 cooldown=0
 sparkle=0
 dog_done_score=0
end

function remaining()
 local r=0
 for c in all(cells) do
  r+=c.tangle+c.dirt+c.fur+c.wet
 end
 return r
end

function _update60()
 wag+=1
 update_particles()
 if sparkle>0 then sparkle-=1 end
 if cooldown>0 then cooldown-=1 end

 if state=="title" then
  if btnp(4) or btnp(5) then
   round=1
   shift_score=0
   reset_dog()
   state="play"
   sfx(4)
  end
  return
 end

 if state=="round_done" or state=="timeout" then
  if btnp(4) or btnp(5) then
   if round>=shift_len then
    if shift_score>best_shift then best_shift=shift_score end
    state="shift_done"
   else
    round+=1
    reset_dog()
    state="play"
   end
  end
  return
 end

 if state=="shift_done" then
  if btnp(4) or btnp(5) then state="title" end
  return
 end

 dog_time-=1
 if dog_time<=0 then
  dog_time=0
  state="timeout"
  sfx(5)
  return
 end

 if btn(0) then cursor.x-=1 end
 if btn(1) then cursor.x+=1 end
 if btn(2) then cursor.y-=1 end
 if btn(3) then cursor.y+=1 end
 cursor.x=mid(8,cursor.x,120)
 cursor.y=mid(12,cursor.y,114)

 if btnp(5) then
  tool=tool%#tools+1
  sfx(6)
 end

 if btn(4) and cooldown==0 then
  if apply_tool() then
   sfx(tools[tool].sfx)
  end
  cooldown=4
 end

 if remaining()==0 then
  state="round_done"
  local bonus=flr(dog_time/60)*5
  shift_score+=bonus
  dog_done_score=bonus
  sfx(4)
  burst_celebration()
 end
end

function apply_tool()
 local hit=false
 local t=tools[tool].n
 for c in all(cells) do
  local cx=cox+c.gx*cw+2
  local cy=coy+c.gy*cw+2
  local dx=cx-cursor.x
  local dy=cy-cursor.y
  if dx*dx+dy*dy<=49 then
   if t=="brush" and c.tangle>0 then
    c.tangle-=1 hit=true shift_score+=1
    spawn_particles(cx,cy,14,3,1)
    spawn_particles(cx,cy,2,2,3)
   elseif t=="suds" and c.dirt>0 then
    c.dirt-=1 hit=true shift_score+=1
    c.wet=min(3,c.wet+1)
    spawn_particles(cx,cy,7,4,1)
    spawn_particles(cx,cy,12,2,2)
   elseif t=="snip" and c.fur>0 then
    c.fur-=1 hit=true shift_score+=1
    spawn_particles(cx,cy-2,10,3,3)
    spawn_particles(cx,cy-2,9,2,3)
   elseif t=="blow" and c.wet>0 then
    c.wet-=1 hit=true shift_score+=1
    spawn_particles(cx,cy,12,3,2)
    spawn_particles(cx,cy,7,2,1)
   end
  end
 end
 if hit then sparkle=6 end
 return hit
end

function spawn_particles(x,y,col,n,kind)
 for i=1,n do
  add(particles,{
   x=x+rnd(3)-1.5,
   y=y+rnd(3)-1.5,
   vx=(rnd(2)-1)*0.7,
   vy=-rnd(1.6)-0.3,
   col=col,
   life=10+flr(rnd(8)),
   kind=kind,
  })
 end
end

function update_particles()
 for p in all(particles) do
  p.x+=p.vx
  p.y+=p.vy
  p.vy+=0.09
  p.life-=1
  if p.life<=0 then del(particles,p) end
 end
end

function burst_celebration()
 local hx,hy=cox+cgw*cw/2,coy+cgh*cw/2
 for i=0,15 do
  local a=i/16
  add(particles,{
   x=hx,y=hy,
   vx=cos(a)*1.4,vy=sin(a)*1.4-0.5,
   col=10+(i%4),
   life=24,kind=1,
  })
 end
end

function draw_particles()
 for p in all(particles) do
  if p.kind==1 then
   circfill(p.x,p.y,1,p.col)
  elseif p.kind==2 then
   pset(p.x,p.y,p.col)
   pset(p.x,p.y+1,p.col)
  else
   pset(p.x,p.y,p.col)
   pset(p.x+1,p.y,p.col)
  end
 end
end

function _draw()
 cls(12)
 if state=="title" then
  draw_title() return
 end
 if state=="shift_done" then
  draw_shift_summary() return
 end

 rectfill(0,100,127,117,4)
 rectfill(8,76,119,100,9)
 line(8,76,119,76,4)
 rectfill(14,100,22,116,4)
 rectfill(105,100,113,116,4)

 draw_dog()
 draw_particles()
 draw_cursor(cursor.x,cursor.y)

 draw_top_hud()
 draw_dock()

 if state=="round_done" then
  rectfill(16,40,111,76,0)
  rect(16,40,111,76,11)
  local m="all groomed!"
  print(m,64-#m*2,46,10)
  print("time bonus "..dog_done_score,38,56,7)
  print("\142 next customer",30,66,6)
 elseif state=="timeout" then
  rectfill(16,40,111,76,0)
  rect(16,40,111,76,8)
  local m="customer left :("
  print(m,64-#m*2,46,8)
  print("\142 next customer",30,66,6)
 end
end

function draw_top_hud()
 rectfill(0,0,127,9,0)
 print("score "..shift_score,2,2,7)
 print("dog "..round.."/"..shift_len,52,2,11)
 local tcol=7
 local secs=flr(dog_time/60)
 if secs<=9 and state=="play" then
  tcol=(wag\10)%2==0 and 8 or 9
 end
 print("time "..secs,84,2,tcol)
end

function draw_dock()
 rectfill(0,118,127,127,5)
 line(0,118,127,118,1)
 for i=1,#tools do
  local x=4+(i-1)*30
  local y=120
  if i==tool then
   rectfill(x-2,y-1,x+25,y+7,1)
   rect(x-2,y-1,x+25,y+7,7)
  end
  local t=tools[i]
  print(i.."."..t.n,x,y+1,t.col)
 end
end

function dog_mood()
 if state=="timeout" then return "sad" end
 if state=="round_done" then return "happy" end
 local ratio=remaining()/start_total
 local secs=flr(dog_time/60)
 if secs<=5 or ratio>=0.75 then return "worry" end
 if ratio<=0.25 then return "happy" end
 return "neutral"
end

function draw_dog()
 local bx0,by0=cox-2,coy-2
 local bx1,by1=cox+cgw*cw+1,coy+cgh*cw+1
 ovalfill(bx0+2,by0+5,bx1+2,by1+5,1)
 ovalfill(bx0,by0,bx1,by1,15)

 circfill(cox+20,coy+10,3,4)
 circfill(cox+40,coy+6,2,4)

 rectfill(cox+8,by1-2,cox+12,by1+8,15)
 rect(cox+8,by1-2,cox+12,by1+8,4)
 rectfill(cox+cgw*cw-12,by1-2,cox+cgw*cw-8,by1+8,15)
 rect(cox+cgw*cw-12,by1-2,cox+cgw*cw-8,by1+8,4)

 local hx,hy=bx0-5,by0+8
 circfill(hx,hy,8,15)
 ovalfill(hx-7,hy-9,hx-2,hy-2,4)
 ovalfill(hx+1,hy-10,hx+6,hy-3,4)
 circfill(hx-6,hy+3,3,6)
 circfill(hx-8,hy+2,1,0)

 local mood=dog_mood()
 local blink=(wag\30)%8==0
 if mood=="happy" then
  line(hx-2,hy-1,hx,hy-2,0)
  line(hx,hy-2,hx,hy-1,0)
 elseif mood=="worry" then
  pset(hx-1,hy-1,0)
  pset(hx-1,hy-2,0)
  pset(hx-1,hy-3,7)
 elseif mood=="sad" then
  line(hx-2,hy,hx,hy-2,0)
 else
  if not blink then
   circfill(hx-1,hy-1,1,0)
   pset(hx-1,hy-2,7)
  else
   line(hx-2,hy-1,hx,hy-1,0)
  end
 end

 if mood=="happy" or mood=="neutral" then
  line(hx-7,hy+5,hx-5,hy+5,0)
  if mood=="happy" then pset(hx-7,hy+4,0) pset(hx-5,hy+4,0) end
 elseif mood=="worry" then
  pset(hx-6,hy+5,0)
 else
  line(hx-7,hy+6,hx-5,hy+5,0)
 end

 local tx,ty=bx1-1,by0+8
 local wagspeed=mood=="happy" and 20 or 60
 local sw=sin(wag/wagspeed)*(mood=="happy" and 3 or 2)
 if mood=="sad" then sw=2 end
 line(tx,ty,tx+5,ty-3+sw,15)
 line(tx,ty+1,tx+6,ty-2+sw,15)

 for c in all(cells) do
  local x=cox+c.gx*cw
  local y=coy+c.gy*cw
  if c.fur>0 then
   local col=10
   if c.fur>=3 then col=9 end
   for i=0,3 do
    local h=1+c.fur+(i%2)
    line(x+i,y-h,x+i,y,col)
   end
  end
  if c.dirt>0 then
   local col=4
   if c.dirt>=3 then col=2 end
   rectfill(x,y,x+cw-1,y+cw-1,col)
   pset(x+1,y+1,0)
   if c.dirt>=2 then pset(x+2,y+2,0) end
  end
  if c.tangle>0 then
   local col=14
   if c.tangle>=2 then col=8 end
   if c.tangle>=3 then col=2 end
   rectfill(x,y,x+cw-1,y+cw-1,col)
   pset(x+1,y,0)
   pset(x,y+2,0)
   if c.tangle>=2 then
    pset(x+2,y+1,0)
    pset(x+3,y+3,0)
   end
  end
  if c.wet>0 then
   local col=12
   if c.wet>=3 then col=1 end
   pset(x,y+1,col)
   pset(x+2,y,col)
   pset(x+3,y+2,col)
   if c.wet>=2 then pset(x+1,y+3,col) end
  end
 end
end

function draw_cursor(x,y)
 local t=tools[tool].n
 if t=="brush" then draw_brush(x,y)
 elseif t=="suds" then draw_suds(x,y)
 elseif t=="snip" then draw_snip(x,y)
 elseif t=="blow" then draw_blow(x,y) end
 if sparkle>0 then circ(x,y,sparkle,10) end
 pset(x,y,8)
end

function draw_brush(x,y)
 local hx=x-3
 local hy=y-6
 rectfill(hx,hy,hx+5,hy+1,9)
 rect(hx,hy,hx+5,hy+1,4)
 for i=0,5 do
  line(hx+i,hy+2,hx+i,hy+3+(i%2),7)
 end
end

function draw_suds(x,y)
 rectfill(x-2,y-7,x+2,y-2,12)
 rect(x-2,y-7,x+2,y-2,1)
 rectfill(x-1,y-9,x+1,y-7,7)
 pset(x,y-1,12)
 pset(x-2,y,7)
 pset(x+2,y+1,7)
end

function draw_snip(x,y)
 line(x-3,y-5,x,y,6)
 line(x+3,y-5,x,y,6)
 circ(x-3,y-5,1,5)
 circ(x+3,y-5,1,5)
 pset(x,y-1,8)
end

function draw_blow(x,y)
 rectfill(x-1,y-6,x+5,y-3,5)
 rect(x-1,y-6,x+5,y-3,0)
 rectfill(x+1,y-3,x+3,y,5)
 line(x-2,y-5,x-3,y-5,10)
 line(x-2,y-4,x-4,y-4,9)
end

function draw_title()
 cls(1)
 for i=0,30 do
  pset((i*23+wag\2)%128,(i*47)%128,2)
 end
 rectfill(0,30,127,80,12)
 line(0,30,127,30,7)
 line(0,80,127,80,4)
 print("dog groomer",36,38,7)
 print("a pup-up barber sim",22,48,6)
 local hx,hy=64,62
 circfill(hx,hy,8,15)
 ovalfill(hx-7,hy-9,hx-2,hy-2,4)
 ovalfill(hx+1,hy-10,hx+6,hy-3,4)
 circfill(hx-6,hy+3,3,6)
 circfill(hx-8,hy+2,1,0)
 circfill(hx-1,hy-1,1,0)
 pset(hx-1,hy-2,7)
 line(hx-2,hy-1,hx,hy-2,0)
 line(hx,hy-2,hx,hy-1,0)
 line(hx-7,hy+5,hx-5,hy+5,0)
 print("arrows: move",30,90,7)
 print("z: groom   x: switch tool",16,98,7)
 if (wag\20)%2==0 then
  print("press \142 to start a shift",14,112,10)
 end
 if best_shift>0 then
  print("best shift "..best_shift,32,120,9)
 end
end

function draw_shift_summary()
 cls(1)
 for p in all(particles) do
  circfill(p.x,p.y,1,p.col)
 end
 rectfill(8,28,119,100,0)
 rect(8,28,119,100,11)
 local m="shift complete!"
 print(m,64-#m*2,36,10)
 print("dogs groomed "..shift_len,28,52,7)
 print("final score "..shift_score,30,62,7)
 if shift_score>=best_shift then
  print("new best!",46,72,9)
 else
  print("best "..best_shift,48,72,6)
 end
 if (wag\20)%2==0 then
  print("\142 back to title",32,86,6)
 end
end

__gfx__
__sfx__
00010000180601c060180601c06000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002000014040180401c0402204000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000100003006000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000400001406014060140601406014060000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000600001805022050270502b05000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000600001805014050100500c05008050000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000100002a06000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
